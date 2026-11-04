// =====================================================================
//  LOGIKA GRY: fale, zombie, budynki, jednostki, walka, ekonomia, zapis
// =====================================================================
import * as THREE from 'three';
import {
  MAP, DIFFICULTY, DIFFICULTY_PER_LEVEL, levelSpeedBonus, BOSS_SPEED_RATIO, ZOMBIE_TYPES, ZOMBIE_BASE,
  BUILDINGS, UNITS, UPGRADES, RESOURCE_BONUS, BARRACKS_MULT, upgradeCost, ARMATA_SLOTS, START, EXCHANGE,
  SELL_REFUND, EARLY_WAVE_BONUS, LIMITS,
} from './config.js';
import { createZombieRig, createSoldierRig, createTankRig } from './rig.js';
import { createBuildingMesh, createGhost, setGhostOk } from './buildings.js';
import { rand, pick, clamp } from './utils.js';

const SAVE_KEY = 'zombie2.save';
const BEST_KEY = 'zombie2.best';

// ----------------------------------------------------------------- SIATKA PRZESTRZENNA
class SpatialHash {
  constructor(cell, minX, minZ, maxX, maxZ) {
    this.cell = cell; this.minX = minX; this.minZ = minZ;
    this.cols = Math.ceil((maxX - minX) / cell); this.rows = Math.ceil((maxZ - minZ) / cell);
    this.cells = Array.from({ length: this.cols * this.rows }, () => []);
  }
  _idx(x, z) {
    const cx = clamp(Math.floor((x - this.minX) / this.cell), 0, this.cols - 1);
    const cz = clamp(Math.floor((z - this.minZ) / this.cell), 0, this.rows - 1);
    return cz * this.cols + cx;
  }
  rebuild(list) {
    for (const c of this.cells) c.length = 0;
    for (const e of list) this.cells[this._idx(e.x, e.z)].push(e);
  }
  query(x, z, r, cb) {
    const c0 = clamp(Math.floor((x - r - this.minX) / this.cell), 0, this.cols - 1);
    const c1 = clamp(Math.floor((x + r - this.minX) / this.cell), 0, this.cols - 1);
    const r0 = clamp(Math.floor((z - r - this.minZ) / this.cell), 0, this.rows - 1);
    const r1 = clamp(Math.floor((z + r - this.minZ) / this.cell), 0, this.rows - 1);
    for (let rr = r0; rr <= r1; rr++) for (let cc = c0; cc <= c1; cc++) {
      const cell = this.cells[rr * this.cols + cc];
      for (let i = 0; i < cell.length; i++) cb(cell[i]);
    }
  }
}

const angDiff = (a, b) => (((b - a) % (Math.PI * 2)) + Math.PI * 3) % (Math.PI * 2) - Math.PI;
const angleLerp = (a, b, t) => {
  let d = ((b - a + Math.PI) % (Math.PI * 2) + Math.PI * 2) % (Math.PI * 2) - Math.PI;
  return a + d * Math.min(1, t);
};

// =====================================================================
export class Game {
  constructor({ scene, world, effects, audio }) {
    this.scene = scene; this.world = world; this.fx = effects; this.audio = audio;
    this.listeners = {};
    this.zombieRig = createZombieRig(scene, LIMITS.zombies + 1);
    this.soldierRig = createSoldierRig(scene, LIMITS.units);
    this.tankRig = createTankRig(scene, LIMITS.tanks);
    this.hash = new SpatialHash(2.5, -MAP.halfW - 20, -MAP.halfD - 20, MAP.halfW + 20, MAP.halfD + 20);
    this.unitHash = new SpatialHash(2.5, -MAP.halfW - 20, -MAP.halfD - 20, MAP.halfW + 20, MAP.halfD + 20);
    this.base = { kind: 'base', x: MAP.baseX, z: MAP.baseZ, radius: 6.2 };
    this.ghost = null;
    this.selected = null;
    this.selectRing = new THREE.Mesh(new THREE.RingGeometry(0.92, 1, 48), new THREE.MeshBasicMaterial({
      color: new THREE.Color(1.5, 1.3, 0.4), transparent: true, opacity: 0.9, depthWrite: false, toneMapped: false }));
    this.selectRing.rotation.x = -Math.PI / 2;
    this.selectRing.position.y = 0.06;
    this.selectRing.visible = false;
    scene.add(this.selectRing);
    this.reset(2);
  }

  on(ev, cb) { (this.listeners[ev] ||= []).push(cb); }
  emit(ev, ...a) { for (const cb of this.listeners[ev] || []) cb(...a); }

  // ================================================================ STAN
  reset(difficultyIndex = 2) {
    // usuń stare obiekty
    for (const b of this.buildings || []) this._removeBuildingMesh(b);
    this.fx.clear();
    this.cancelBuild();
    this.deselect();
    this.difficultyIndex = difficultyIndex;
    this.level = 1;
    this.gold = START.gold; this.wood = START.wood;
    this.baseHP = this.maxBaseHP = START.baseHP;
    this.kills = 0; this.levelKills = 0;
    this.zombies = []; this.buildings = []; this.units = []; this.tanks = [];
    this.goldPerSecond = 0; this.woodPerSecond = 0;
    this.over = false; this.paused = false;
    this.stats = { shots: 0, built: 0, lost: 0, bosses: 0, time: 0, kinds: { walker: 0, runner: 0, brute: 0 } };
    this.slotUsed = [false, false, false, false];
    ARMATA_SLOTS.forEach((_, i) => this.world.setSlotUsed(i, false));
    this._updateDifficulty();
    this.setupLevel();
  }

  get diff() { return DIFFICULTY[this.difficultyIndex]; }
  _updateDifficulty() {
    this.difficultyScale = this.diff.scale + (this.level - 1) * DIFFICULTY_PER_LEVEL;
    this.speedMult = this.diff.speedMult;
  }
  setDifficulty(i) {
    this.difficultyIndex = i;
    this._updateDifficulty();
    this.emit('notify', `🎚️ Trudność: ${this.diff.name} (fale co ${this.diff.waveTime}s)`);
    this.emit('change');
  }

  setupLevel() {
    this.levelGoal = this.level === 1 ? 10 : this.level * 10;
    this.maxWaves = Math.ceil(this.levelGoal / 10);
    this.currentWave = 0;
    this.waveTimer = this.diff.waveTime - 5;
    this.toSpawn = 0;
    this.spawnTimer = 0;
    this.bossReleased = false;
    this.completeTimer = -1;
    this.zombies = [];
    this.world.closeCage();
    this._spawnBoss();
    this.emit('change');
  }

  // ================================================================ ZOMBIE
  _zombieTypeForLevel() {
    const avail = Object.entries(ZOMBIE_TYPES).filter(([, t]) => t.minLevel <= this.level);
    const total = avail.reduce((s, [, t]) => s + t.weight, 0);
    let r = Math.random() * total;
    for (const [k, t] of avail) { r -= t.weight; if (r <= 0) return k; }
    return 'walker';
  }

  _makeZombie(typeKey, x, z) {
    const t = ZOMBIE_TYPES[typeKey];
    const skin = new THREE.Color(pick(t.skins)).offsetHSL(rand(-0.02, 0.02), 0, rand(-0.05, 0.05));
    const cloth = new THREE.Color(pick(t.cloth)).offsetHSL(0, 0, rand(-0.05, 0.05));
    return {
      kind: 'zombie', type: typeKey, x, z, y: 0, rot: Math.PI / 2, scale: t.scale * rand(0.94, 1.06),
      vx: 0, vz: 0, phase: Math.random() * 10, seed: Math.random() * 100, state: 'walk', t: 0,
      hunch: 0.3, sway: 0, headTilt: 0, headYaw: 0, armL: -1.3, armR: -1.3, legL: 0, legR: 0, tilt: 0,
      skin, cloth, pants: cloth.clone().multiplyScalar(0.6), flash: 0,
      target: null, retarget: Math.random() * 0.4, attackTimer: 0, groanTimer: rand(2, 10),
    };
  }

  spawnZombie() {
    const typeKey = this._zombieTypeForLevel();
    const t = ZOMBIE_TYPES[typeKey];
    const z = rand(-MAP.halfD + 6, MAP.halfD - 6);
    const x = MAP.spawnX + rand(-2, 3);
    const e = this._makeZombie(typeKey, x, z);
    e.maxHP = e.hp = ZOMBIE_BASE.hp(this.level) * this.difficultyScale * t.hp;
    e.speed = (ZOMBIE_BASE.speed + levelSpeedBonus(this.level)) * this.speedMult * t.speed;
    e.dmg = ZOMBIE_BASE.dmg(this.level) * this.difficultyScale * t.dmg;
    e.state = 'rise'; e.y = -2.2;
    this.zombies.push(e);
    this.fx.dust(x, z, 10, [0.25, 0.18, 0.2]);
  }

  _spawnBoss() {
    const e = this._makeZombie('brute', MAP.spawnX, 0);
    const n = this.levelGoal;
    e.isBoss = true; e.locked = true; e.state = 'caged';
    e.scale = 2.6;
    e.maxHP = e.hp = n * ZOMBIE_BASE.hp(this.level) * 0.7 * this.difficultyScale;
    e.dmg = n * ZOMBIE_BASE.dmg(this.level) * 0.15 * this.difficultyScale;
    e.speed = (2.1 + levelSpeedBonus(this.level) * BOSS_SPEED_RATIO) * this.speedMult;
    e.skin = new THREE.Color(0x8a4a6a); e.cloth = new THREE.Color(0x2a1a2a); e.pants = new THREE.Color(0x1a1018);
    this.zombies.push(e);
  }

  releaseBoss() {
    const boss = this.zombies.find(z => z.isBoss);
    this.bossReleased = true;
    this.world.openCage();
    if (boss) { boss.locked = false; boss.state = 'walk'; }
    this.audio.groan(MAP.spawnX, true);
    this.emit('announce', '👑 KLATKA OTWARTA!', 'BOSS ATAKUJE', 'boss');
    this.emit('camShake', 0.8);
  }

  get aliveRegular() { let n = 0; for (const z of this.zombies) if (!z.isBoss && z.state !== 'dying') n++; return n; }
  get boss() { return this.zombies.find(z => z.isBoss && z.state !== 'dying'); }

  damageZombie(z, dmg, kx = 0, kz = 0) {
    if (z.state === 'dying' || z.locked) return;
    z.hp -= dmg;
    z.flash = 1;
    z.x += kx; z.z += kz;
    if (z.hp <= 0) this._killZombie(z);
  }

  _killZombie(z) {
    z.state = 'dying'; z.t = 0; z.hp = 0;
    this.fx.bloodBurst(z.x, 1.2 * z.scale, z.z, z.isBoss ? 60 : 14);
    this.fx.splat(z.x, z.z, z.isBoss ? 4 : 1.3 * z.scale);
    this.audio.splat(z.x);
    if (z.isBoss) {
      const g = 200 + this.level * 50, w = 150 + this.level * 40;
      this.gold += g; this.wood += w;
      this.lastReward = { gold: g, wood: w };
      this.stats.bosses++;
      this.completeTimer = 2.2;
      this.emit('camShake', 1.2);
      this.fx.explosion(z.x, z.z, 4, true);
      this.emit('floater', z.x, 6, z.z, `+${g} 💰  +${w} 🪵`, '#ffd76a');
      return;
    }
    this.kills++; this.levelKills++;
    this.stats.kinds[z.type]++;
    const mult = ZOMBIE_TYPES[z.type].hp;
    if (Math.random() < 0.65) {
      const g = Math.round((6 + Math.floor(this.currentWave / 2)) * Math.max(1, mult * 0.8));
      this.gold += g;
      this.emit('floater', z.x, 2.5 * z.scale, z.z, `+${g} 💰`, '#ffd76a');
    } else {
      const w = Math.round(4 * Math.max(1, mult * 0.8));
      this.wood += w;
      this.emit('floater', z.x, 2.5 * z.scale, z.z, `+${w} 🪵`, '#d8b27a');
    }
    if (this.levelKills >= this.levelGoal && !this.bossReleased) this.releaseBoss();
    this.emit('change');
  }

  _updateZombies(dt) {
    const zs = this.zombies;
    this.hash.rebuild(zs);
    const targets = [this.base, ...this.buildings, ...this.units, ...this.tanks];
    for (let i = zs.length - 1; i >= 0; i--) {
      const z = zs[i];
      z.t += dt;
      z.flash = Math.max(0, z.flash - dt * 9);
      const ph = z.phase;

      if (z.state === 'dying') {
        const k = Math.min(1, z.t / 0.45);
        z.tilt = -1.5 * (k * k);
        z.armL = z.armR = -2.6 * k; z.legL = 0.3 * k; z.legR = -0.2 * k;
        if (z.t > 1.2) z.y = -(z.t - 1.2) * 0.9 * z.scale;
        if (z.t > 2.8) { zs.splice(i, 1); }
        continue;
      }
      if (z.state === 'caged') {
        // boss krąży i ryczy w klatce
        z.phase += dt * 1.6;
        z.rot = Math.PI / 2 + Math.sin(z.t * 0.5) * 0.6;
        z.legL = Math.sin(z.phase) * 0.3; z.legR = -z.legL;
        const roar = (Math.sin(z.t * 0.9) > 0.85);
        z.armL = roar ? -2.7 : -1.2 + Math.sin(z.phase) * 0.2;
        z.armR = roar ? -2.7 : -1.2 - Math.sin(z.phase) * 0.2;
        z.headTilt = roar ? -0.4 : 0.15;
        if (roar && Math.random() < dt * 0.6) this.audio.groan(z.x, true);
        if (Math.random() < dt * 8) this.fx.magic(z.x, 0.2, z.z);
        continue;
      }
      if (z.state === 'rise') {
        const k = Math.min(1, z.t / 1.1);
        z.y = -2.2 * (1 - k) * (1 - k);
        z.armL = z.armR = -2.8 + k * 1.4;
        z.hunch = 0.6 - k * 0.3;
        if (Math.random() < dt * 20) this.fx.dust(z.x, z.z, 1, [0.25, 0.18, 0.2]);
        if (k >= 1) { z.state = 'walk'; z.y = 0; }
        continue;
      }

      // --- wybór celu
      z.retarget -= dt;
      if (!z.target || z.retarget <= 0 || z.target.dead) {
        let best = this.base, bd = Infinity;
        for (const t of targets) {
          if (t.dead) continue;
          const r = t.kind === 'base' ? t.radius : t.kind === 'building' ? t.size * 0.5 : 0.5;
          const d = Math.hypot(t.x - z.x, t.z - z.z) - r;
          if (d < bd) { bd = d; best = t; }
        }
        z.target = best; z.retarget = 0.35 + Math.random() * 0.2;
      }
      const tg = z.target;
      const contact = (tg.kind === 'base' ? tg.radius : tg.kind === 'building' ? tg.size * 0.5 + 0.7 : 1.0) + (z.isBoss ? 1.8 : 0.2 * z.scale);
      const dx = tg.x - z.x, dz = tg.z - z.z;
      const dist = Math.hypot(dx, dz) || 0.001;
      const nx = dx / dist, nz = dz / dist;

      if (dist > contact) {
        z.state = 'walk';
        const sp = z.speed;
        let mx = nx * sp, mz = nz * sp;
        // rozpychanie się w tłumie
        const sr = 0.9 * z.scale;
        this.hash.query(z.x, z.z, sr + 1.2, (o) => {
          if (o === z || o.state === 'dying' || o.locked) return;
          const ox = z.x - o.x, oz = z.z - o.z;
          const d2 = ox * ox + oz * oz;
          const min = (sr + 0.9 * o.scale) * 0.7;
          if (d2 < min * min && d2 > 1e-6) {
            const d = Math.sqrt(d2), push = (min - d) / min * 3.5;
            mx += ox / d * push; mz += oz / d * push;
          }
        });
        z.vx = mx; z.vz = mz;
        z.x += mx * dt; z.z += mz * dt;
        // nie przenikaj przez budynki
        for (const b of this.buildings) {
          const r = b.size * 0.55 + 0.3 * z.scale;
          const ox = z.x - b.x, oz = z.z - b.z;
          const d = Math.hypot(ox, oz);
          if (d < r && d > 0.001) { z.x = b.x + ox / d * r; z.z = b.z + oz / d * r; }
        }
        z.z = clamp(z.z, -MAP.halfD + 0.5, MAP.halfD - 0.5);
        z.rot = angleLerp(z.rot, Math.atan2(mx, mz), dt * 6);
        // animacja chodu
        const runner = z.type === 'runner';
        z.phase += dt * sp * (runner ? 2.4 : 2.8) / z.scale;
        const p = z.phase;
        z.legL = Math.sin(p) * (runner ? 0.8 : 0.5); z.legR = -z.legL;
        z.armL = (runner ? -0.4 : -1.35) + Math.sin(p + Math.PI) * (runner ? 0.9 : 0.2);
        z.armR = (runner ? -0.4 : -1.25) + Math.sin(p) * (runner ? 0.9 : 0.2);
        z.hunch = runner ? 0.55 : z.type === 'brute' ? 0.4 : 0.28;
        z.sway = Math.sin(p * 0.5) * 0.1;
        z.y = Math.abs(Math.sin(p)) * 0.07 * z.scale;
      } else {
        // atak
        z.state = 'attack';
        z.rot = angleLerp(z.rot, Math.atan2(nx, nz), dt * 8);
        const a = z.t * (z.isBoss ? 5 : 9);
        z.armL = -1.7 + Math.sin(a) * 0.75; z.armR = -1.7 + Math.sin(a + Math.PI) * 0.75;
        z.legL = z.legR = 0; z.hunch = 0.45 + Math.sin(a) * 0.08; z.y = 0;
        const dps = z.dmg * ZOMBIE_BASE.dpsFactor;
        if (tg.kind === 'base') {
          this._damageBase(dps * dt);
        } else {
          tg.hp -= dps * dt;
          tg.flash = Math.max(tg.flash || 0, 0.3);
          z.attackTimer -= dt;
          if (z.attackTimer <= 0) { z.attackTimer = 0.5; this.audio.hit(z.x); if (tg.kind === 'building') this.fx.sparks(tg.x, 1, tg.z, 2); }
        }
      }
      z.headTilt = 0.2 + Math.sin(z.t * 1.3 + z.seed) * 0.15;
      z.headYaw = Math.sin(z.t * 0.7 + z.seed) * 0.3;
      z.groanTimer -= dt;
      if (z.groanTimer <= 0) { z.groanTimer = rand(4, 14); this.audio.groan(z.x, z.isBoss); }
    }
  }

  _damageBase(amount) {
    if (this.over) return;
    this.baseHP -= amount;
    this.baseFlash = 1;
    this.audio.baseHit();
    if (this.baseHP <= 0) {
      this.baseHP = 0;
      this.over = true;
      this.fx.explosion(MAP.baseX, 0, 6, true);
      this.audio.explosion(MAP.baseX, true);
      this.audio.gameOver();
      let best = 0;
      try { best = +localStorage.getItem(BEST_KEY) || 0; if (this.level > best) localStorage.setItem(BEST_KEY, this.level); localStorage.removeItem(SAVE_KEY); } catch (e) {}
      this.emit('gameOver', { level: this.level, kills: this.kills, wave: this.currentWave, maxWaves: this.maxWaves, best: Math.max(best, this.level), stats: this.stats });
    }
  }

  // ================================================================ FALE
  _updateWaves(dt) {
    if (this.bossReleased) return;
    if (this.toSpawn > 0) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        if (this.zombies.length < LIMITS.zombies) {
          this.spawnZombie();
          this.toSpawn--;
          this.spawnTimer = 0.5;
          this.emit('change');
        } else this.spawnTimer = 0.3;
      }
      return;
    }
    this.waveTimer += dt;
    if (this.waveTimer >= this.diff.waveTime && this.canCallWave) this._startWave();
  }

  get canCallWave() {
    return !this.bossReleased && this.toSpawn === 0 && this.levelKills + this.aliveRegular < this.levelGoal;
  }
  get waveCountdown() { return Math.max(0, this.diff.waveTime - this.waveTimer); }

  _startWave() {
    this.waveTimer = 0;
    this.currentWave = Math.min(this.maxWaves, this.currentWave + 1);
    this.toSpawn = Math.min(10, this.levelGoal - (this.levelKills + this.aliveRegular));
    this.audio.horn();
    this.emit('announce', `🌊 FALA ${this.currentWave}/${this.maxWaves}`, `${this.toSpawn} zombie nadciąga`, 'wave');
    this.emit('change');
  }

  callWaveEarly() {
    if (!this.canCallWave) return;
    const bonus = Math.round(this.waveCountdown / this.diff.waveTime * EARLY_WAVE_BONUS * (1 + this.level * 0.2));
    if (bonus > 0) { this.gold += bonus; this.emit('notify', `⏩ Fala wcześniej: +${bonus} 💰`); this.audio.coin(); }
    this._startWave();
  }

  nextLevel() {
    this.level++;
    this.levelKills = 0;
    this._updateDifficulty();
    this.wood += 40; this.gold += 50;
    this.setupLevel();
    this.save();
  }

  // ================================================================ BUDOWANIE
  canAfford(type) {
    const c = BUILDINGS[type].cost;
    return (!c.wood || this.wood >= c.wood) && (!c.gold || this.gold >= c.gold);
  }
  limitReached(type) {
    const def = BUILDINGS[type];
    if (type === 'wielkaArmata') return this.slotUsed.every(Boolean);
    if (def.limit) return this.buildings.filter(b => b.type === type).length >= def.limit;
    if (type === 'soldier') return this.units.length >= LIMITS.units;
    return false;
  }

  selectBuild(type) {
    if (this.buildType === type) { this.cancelBuild(); return; }
    if (this.limitReached(type)) { this.emit('notify', type === 'wielkaArmata' ? '🎯 Wszystkie platformy zajęte (4/4)' : `${BUILDINGS[type].icon} Limit osiągnięty`); this.audio.error(); return; }
    if (!this.canAfford(type)) { this.emit('notify', '❌ Za mało surowców!'); this.audio.error(); return; }
    this.cancelBuild();
    this.deselect();
    this.buildType = type;
    this.ghost = createGhost(type);
    this.ghost.visible = false;
    this.scene.add(this.ghost);
    this.world.overlay.visible = true;
    this.emit('buildMode', type);
    this.audio.click();
  }

  cancelBuild() {
    if (this.ghost) { this.scene.remove(this.ghost); this.ghost = null; }
    this.buildType = null;
    this.touchCell = null;
    this.world.overlay.visible = false;
    this.world.showRange(0, 0, 0);
    this.emit('buildMode', null);
  }

  _snap(type, x, z) {
    if (BUILDINGS[type].slotOnly) {
      let best = -1, bd = Infinity;
      ARMATA_SLOTS.forEach((s, i) => {
        if (this.slotUsed[i]) return;
        const d = Math.hypot(s.x - x, s.z - z);
        if (d < bd) { bd = d; best = i; }
      });
      if (best < 0) return { x, z, slot: -1 };
      return { x: ARMATA_SLOTS[best].x, z: ARMATA_SLOTS[best].z, slot: best, far: bd > 12 };
    }
    return { x: Math.round(x), z: Math.round(z) };
  }

  canPlace(type, x, z, slot) {
    const def = BUILDINGS[type];
    if (def.slotOnly) return slot >= 0 && !this.slotUsed[slot];
    const s = def.size, h = s / 2;
    if (Math.abs(x) > MAP.halfW - h - 1 || Math.abs(z) > MAP.halfD - h - 0.5) return false;
    if (Math.abs(x - MAP.baseX) < 6.5 + h && Math.abs(z - MAP.baseZ) < 6.5 + h) return false;
    if (x < MAP.spawnX + 9) return false;
    for (const sl of ARMATA_SLOTS) if (Math.abs(sl.x - x) < 2.4 + h && Math.abs(sl.z - z) < 2.4 + h) return false;
    for (const b of this.buildings) {
      const m = (s + b.size) / 2 + 0.2;
      if (Math.abs(b.x - x) < m && Math.abs(b.z - z) < m) return false;
    }
    return true;
  }

  pointerMove(x, z) {
    this.hover = { x, z };
    if (!this.buildType || !this.ghost) return;
    if (this.touchCell) return; // na dotyku podgląd stoi w miejscu do potwierdzenia
    this._moveGhost(x, z);
  }

  _moveGhost(x, z) {
    const type = this.buildType;
    const p = this._snap(type, x, z);
    const ok = this.canPlace(type, p.x, p.z, p.slot) && this.canAfford(type);
    this.ghost.visible = true;
    this.ghost.position.set(p.x, BUILDINGS[type].slotOnly ? 0.8 : 0, p.z);
    setGhostOk(this.ghost, ok);
    this.world.overlayMat.uniforms.uCursor.value.set(p.x, p.z);
    this.world.overlayMat.uniforms.uOk.value = ok ? 1 : 0;
    const range = BUILDINGS[type].range || (type === 'soldier' ? UNITS.soldier.range : 0);
    this.world.showRange(p.x, p.z, range, ok);
    return { ...p, ok };
  }

  /** Kliknięcie/stuknięcie w mapę */
  pointerTap(x, z, isTouch) {
    if (this.over) return;
    if (this.buildType) {
      const p = this._snap(this.buildType, x, z);
      if (isTouch) {
        // dotyk: 1. stuknięcie pokazuje podgląd, 2. w to samo miejsce stawia
        const same = this.touchCell && this.touchCell.x === p.x && this.touchCell.z === p.z;
        if (!same) { this.touchCell = null; this._moveGhost(x, z); this.touchCell = { x: p.x, z: p.z }; return; }
      }
      this.touchCell = null;
      this._tryPlace(p);
      return;
    }
    // zaznaczanie budynku
    let hit = null, hd = Infinity;
    for (const b of this.buildings) {
      const d = Math.max(Math.abs(b.x - x), Math.abs(b.z - z));
      if (d < b.size * 0.5 + 0.6 && d < hd) { hd = d; hit = b; }
    }
    if (hit) this.select(hit); else this.deselect();
  }

  _tryPlace(p) {
    const type = this.buildType;
    if (!this.canAfford(type)) { this.emit('notify', '❌ Za mało surowców!'); this.audio.error(); return; }
    if (this.limitReached(type)) { this.cancelBuild(); return; }
    if (!this.canPlace(type, p.x, p.z, p.slot)) { this.emit('notify', '❌ Nie można tu budować'); this.audio.error(); return; }
    const def = BUILDINGS[type];
    this.wood -= def.cost.wood || 0;
    this.gold -= def.cost.gold || 0;
    if (type === 'soldier') this._spawnUnit('soldier', p.x, p.z);
    else this._addBuilding(type, p.x, p.z, p.slot);
    this.stats.built++;
    this.fx.dust(p.x, p.z, 18);
    this.audio.build();
    // zostań w trybie budowania (szybkie stawianie kolejnych), wyjdź gdy brak środków
    if (!this.canAfford(type) || this.limitReached(type)) this.cancelBuild();
    else this._moveGhost(p.x, p.z);
    this.emit('change');
  }

  _addBuilding(type, x, z, slot = -1, data = {}) {
    const def = BUILDINGS[type];
    const { group, anim, muzzle } = createBuildingMesh(type);
    const y = def.slotOnly ? 0.8 : 0;
    group.position.set(x, y, z);
    if (type !== 'wielkaArmata' && type !== 'cannon') group.rotation.y = -Math.PI / 2; // front w stronę zombie
    this.scene.add(group);
    const b = {
      kind: 'building', type, x, z, size: def.size, hp: data.hp ?? def.hp, maxHP: def.hp,
      upgradeLevel: data.upgradeLevel || 0, cooldown: Math.random(), productionTimer: data.productionTimer || 0,
      mesh: group, anim, muzzle, slot, aim: -Math.PI / 2, recoil: 0, fxTimer: Math.random(), flash: 0, buildT: 0,
    };
    if (anim.turret) anim.turret.rotation.y = b.aim;
    if (slot >= 0) { this.slotUsed[slot] = true; this.world.setSlotUsed(slot, true); }
    this.buildings.push(b);
    this._updateProduction();
    return b;
  }

  _removeBuildingMesh(b) {
    this.scene.remove(b.mesh);
    b.mesh.traverse(o => { if (o.isMesh && o.geometry) o.geometry.dispose(); });
  }

  _destroyBuilding(b, sold = false) {
    b.dead = true;
    this._removeBuildingMesh(b);
    this.buildings.splice(this.buildings.indexOf(b), 1);
    if (b.slot >= 0) { this.slotUsed[b.slot] = false; this.world.setSlotUsed(b.slot, false); }
    if (this.selected === b) this.deselect();
    this._updateProduction();
    this.fx.dust(b.x, b.z, 26, [0.4, 0.37, 0.33]);
    if (!sold) {
      this.stats.lost++;
      this.fx.explosion(b.x, b.z, b.size, false);
      this.audio.crumble(b.x);
      this.emit('notify', `💥 Zniszczono: ${BUILDINGS[b.type].name}`);
    }
    this.emit('change');
  }

  _updateProduction() {
    let w = 0, g = 0;
    for (const b of this.buildings) {
      const def = BUILDINGS[b.type];
      const mult = 1 + (RESOURCE_BONUS[b.upgradeLevel] || 0);
      if (def.woodPerSecond) w += Math.round(def.woodPerSecond * mult);
      if (def.goldPerSecond) g += Math.round(def.goldPerSecond * mult);
    }
    this.woodPerSecond = w; this.goldPerSecond = g;
  }

  // ---------------------------------------------------------------- zaznaczanie / ulepszenia
  select(b) {
    this.selected = b;
    this.selectRing.visible = true;
    this.selectRing.position.set(b.x, 0.06, b.z);
    this.selectRing.scale.setScalar(b.size * 0.8 + 0.6);
    const def = BUILDINGS[b.type];
    if (def.range) this.world.showRange(b.x, b.z, def.range, true);
    this.audio.click();
    this.emit('select', b);
  }
  deselect() {
    if (!this.selected) return;
    this.selected = null;
    this.selectRing.visible = false;
    this.world.showRange(0, 0, 0);
    this.emit('select', null);
  }

  upgradeInfo(b) {
    const def = BUILDINGS[b.type];
    if (!def.upgrades) return null;
    return UPGRADES[def.upgrades].map((tier, i) => {
      const cost = upgradeCost(b.type, i);
      return { level: i + 1, desc: tier.desc, cost, owned: b.upgradeLevel > i, available: b.upgradeLevel === i,
        affordable: this.wood >= cost.wood && this.gold >= cost.gold };
    });
  }

  buyUpgrade(b, level) {
    const info = this.upgradeInfo(b);
    const tier = info?.[level - 1];
    if (!tier || !tier.available || !tier.affordable) { this.audio.error(); return; }
    this.wood -= tier.cost.wood; this.gold -= tier.cost.gold;
    b.upgradeLevel = level;
    this._updateProduction();
    this.fx.heal(b.x, b.z);
    this.audio.fanfare();
    this.emit('notify', `⬆️ ${BUILDINGS[b.type].name}: poziom ${level}`);
    this.emit('change');
    this.emit('select', b);
  }

  repairCost(b) {
    const c = BUILDINGS[b.type].cost;
    const k = (1 - b.hp / b.maxHP) * 0.5;
    return { wood: Math.ceil((c.wood || 0) * k), gold: Math.ceil((c.gold || 0) * k) };
  }
  repair(b) {
    const c = this.repairCost(b);
    if (b.hp >= b.maxHP || this.wood < c.wood || this.gold < c.gold) { this.audio.error(); return; }
    this.wood -= c.wood; this.gold -= c.gold;
    b.hp = b.maxHP;
    this.fx.heal(b.x, b.z);
    this.audio.build();
    this.emit('change');
    this.emit('select', b);
  }
  sellValue(b) {
    const c = BUILDINGS[b.type].cost;
    const k = SELL_REFUND * (b.hp / b.maxHP);
    return { wood: Math.floor((c.wood || 0) * k), gold: Math.floor((c.gold || 0) * k) };
  }
  sell(b) {
    const v = this.sellValue(b);
    this.wood += v.wood; this.gold += v.gold;
    this.audio.coin();
    this.emit('notify', `💸 Sprzedano: +${v.wood} 🪵 +${v.gold} 💰`);
    this._destroyBuilding(b, true);
  }

  exchange(kind) {
    const e = EXCHANGE[kind];
    if (kind === 'goldToWood' && this.gold >= e.give) { this.gold -= e.give; this.wood += e.get; }
    else if (kind === 'woodToGold' && this.wood >= e.give) { this.wood -= e.give; this.gold += e.get; }
    else { this.audio.error(); return; }
    this.audio.coin();
    this.emit('change');
  }

  // ================================================================ JEDNOSTKI
  _spawnUnit(type, x, z, data = {}) {
    const isTank = type === 'tank';
    const list = isTank ? this.tanks : this.units;
    if (list.length >= (isTank ? LIMITS.tanks : LIMITS.units)) return null;
    const def = UNITS[type];
    const u = {
      kind: 'unit', type, x, z, y: 0, rot: -Math.PI / 2, scale: 1, hp: data.hp ?? def.hp, maxHP: def.hp,
      cooldown: Math.random() * def.fireRate, target: null, retarget: 0, phase: Math.random() * 6,
      legL: 0, legR: 0, recoil: 0, turret: 0, flash: 0, hunch: 0,
      cloth: new THREE.Color(isTank ? 0x56653a : 0x56663a).offsetHSL(0, 0, rand(-0.03, 0.03)),
      pants: new THREE.Color(0x3c4628),
    };
    list.push(u);
    return u;
  }

  _updateUnits(dt, list, isTank) {
    const zs = this.zombies;
    for (let i = list.length - 1; i >= 0; i--) {
      const u = list[i];
      const def = UNITS[u.type];
      u.flash = Math.max(0, u.flash - dt * 4);
      u.recoil = Math.max(0, u.recoil - dt * 6);
      if (u.hp <= 0) {
        u.dead = true;
        list.splice(i, 1);
        this.fx.bloodBurst(u.x, 1, u.z, 12);
        if (isTank) { this.fx.explosion(u.x, u.z, 2.5); this.audio.explosion(u.x); }
        else this.fx.splat(u.x, u.z, 1);
        this.stats.lost++;
        continue;
      }
      u.retarget -= dt;
      if (u.retarget <= 0 || (u.target && (u.target.state === 'dying' || u.target.hp <= 0))) {
        u.retarget = 0.25 + Math.random() * 0.1;
        let best = null, bd = def.sight;
        for (const z of zs) {
          if (z.locked || z.state === 'dying' || z.state === 'rise') continue;
          const d = Math.hypot(z.x - u.x, z.z - u.z);
          if (d < bd) { bd = d; best = z; }
        }
        u.target = best;
      }
      let moving = false;
      const t = u.target;
      if (t) {
        const dx = t.x - u.x, dz = t.z - u.z, d = Math.hypot(dx, dz);
        const want = Math.atan2(dx, dz);
        if (isTank) {
          u.turret = angleLerp(u.turret, want - u.rot, dt * 5);
        }
        if (d > def.range - 2) {
          u.x += dx / d * def.speed * dt;
          u.z += dz / d * def.speed * dt;
          moving = true;
          u.rot = angleLerp(u.rot, want, dt * (isTank ? 2.5 : 8));
        } else if (!isTank) u.rot = angleLerp(u.rot, want, dt * 10);

        u.cooldown -= dt;
        if (u.cooldown <= 0 && d <= def.range) {
          const aimed = isTank ? Math.abs(angDiff(u.rot + u.turret, want)) < 0.25
                               : Math.abs(angDiff(u.rot, want)) < 0.35;
          if (aimed) {
            u.cooldown = def.fireRate;
            u.recoil = 1;
            this.stats.shots++;
            const a = isTank ? u.rot + u.turret : u.rot;
            const fx = Math.sin(a), fz = Math.cos(a);
            if (isTank) {
              const mx = u.x + fx * 2.2, mz = u.z + fz * 2.2;
              this.fx.muzzle(mx, 1.35, mz, fx, fz);
              this.audio.cannon(u.x);
              const T = d / 34;
              this.fx.shell(mx, 1.35, mz, t.x + (t.vx || 0) * T, t.z + (t.vz || 0) * T, { speed: 34, arc: 0.6 }, (lx, lz) => this._splash(lx, lz, def.splash, def.damage, false));
            } else {
              const mx = u.x + fx * 1.1 + fz * 0.12, mz = u.z + fz * 1.1 - fx * 0.12;
              this.fx.muzzle(mx, 1.45, mz, fx, fz);
              this.audio.shot(u.x);
              const target = t;
              this.fx.tracer(mx, 1.45, mz, t.x, 1.3 * t.scale, t.z, () => {
                if (target.state !== 'dying') {
                  this.damageZombie(target, def.damage, fx * 0.08, fz * 0.08);
                  this.fx.bloodBurst(target.x, 1.3 * target.scale, target.z, 4, fx, fz);
                }
              });
            }
          }
        }
      } else if (isTank) {
        u.turret = angleLerp(u.turret, 0, dt * 2);
      }
      if (!isTank) {
        if (moving) { u.phase += dt * 9; u.legL = Math.sin(u.phase) * 0.6; u.legR = -u.legL; u.y = Math.abs(Math.sin(u.phase)) * 0.06; }
        else { u.legL *= 0.85; u.legR *= 0.85; u.y = 0; }
        u.hunch = 0.05 + u.recoil * 0.08;
      } else {
        u.hunch = -u.recoil * 0.04;
        if (moving && Math.random() < dt * 6) this.fx.dust(u.x - Math.sin(u.rot) * 1.4, u.z - Math.cos(u.rot) * 1.4, 1);
      }
      u.x = clamp(u.x, -MAP.halfW + 1, MAP.halfW - 1);
      u.z = clamp(u.z, -MAP.halfD + 1, MAP.halfD - 1);
    }
    // rozsuwanie jednostek i wypychanie z budynków
    this.unitHash.rebuild(list);
    for (const u of list) {
      const r = isTank ? 1.6 : 0.6;
      this.unitHash.query(u.x, u.z, r * 2, (o) => {
        if (o === u) return;
        const ox = u.x - o.x, oz = u.z - o.z, d = Math.hypot(ox, oz);
        if (d < r * 2 && d > 1e-4) { const k = (r * 2 - d) * 0.5; u.x += ox / d * k * 0.5; u.z += oz / d * k * 0.5; }
      });
      for (const b of this.buildings) {
        const rr = b.size * 0.55 + r;
        const ox = u.x - b.x, oz = u.z - b.z, d = Math.hypot(ox, oz);
        if (d < rr && d > 1e-4) { u.x = b.x + ox / d * rr; u.z = b.z + oz / d * rr; }
      }
      const bx = u.x - MAP.baseX, bz = u.z - MAP.baseZ, bd = Math.hypot(bx, bz);
      if (bd < 6.5 && bd > 1e-4) { u.x = MAP.baseX + bx / bd * 6.5; u.z = MAP.baseZ + bz / bd * 6.5; }
    }
  }

  // ================================================================ BUDYNKI
  _splash(x, z, radius, dmg, big) {
    this.fx.explosion(x, z, radius, big);
    this.audio.explosion(x, big);
    this.emit('camShake', big ? 0.35 : 0.12);
    this.hash.query(x, z, radius + 1.5, (zm) => {
      if (zm.state === 'dying' || zm.locked) return;
      const d = Math.hypot(zm.x - x, zm.z - z);
      const r = radius + 0.4 * zm.scale;
      if (d > r) return;
      const k = 1 - 0.5 * (d / r);
      const kb = zm.isBoss ? 0 : 0.6 * k;
      this.damageZombie(zm, dmg * k, d > 0.01 ? (zm.x - x) / d * kb : 0, d > 0.01 ? (zm.z - z) / d * kb : 0);
      if (zm.state !== 'dying') this.fx.bloodBurst(zm.x, 1.2 * zm.scale, zm.z, 4);
    });
  }

  _updateBuildings(dt) {
    const zs = this.zombies;
    for (let i = this.buildings.length - 1; i >= 0; i--) {
      const b = this.buildings[i];
      if (b.hp <= 0) { this._destroyBuilding(b); continue; }
      const def = BUILDINGS[b.type];
      const a = b.anim;
      b.buildT = Math.min(1, b.buildT + dt * 3);
      const s = 0.6 + 0.4 * (1 - Math.pow(1 - b.buildT, 3)) + Math.sin(b.buildT * Math.PI) * 0.08;
      b.mesh.scale.set(s, s, s);

      if (a.saw) a.saw.rotation.y += dt * 14;
      if (a.wheel) a.wheel.rotation.z += dt * 2;
      if (a.flag) a.flag.rotation.y = Math.sin(this.stats.time * 3) * 0.35;

      b.fxTimer -= dt;
      if (b.fxTimer <= 0) {
        b.fxTimer = 0.12;
        const hpk = b.hp / b.maxHP;
        if (hpk < 0.5) this.fx.smoke(b.x + rand(-0.5, 0.5), 1.5, b.z + rand(-0.5, 0.5), 1);
        if (hpk < 0.25) this.fx.fire(b.x + rand(-0.6, 0.6), 0.8, b.z + rand(-0.6, 0.6), 1);
        if (a.chimney && Math.random() < 0.6) {
          const v = a.chimney.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), b.mesh.rotation.y);
          this.fx.smoke(b.x + v.x, v.y, b.z + v.z, 1.2);
        }
        if (a.dust && Math.random() < 0.5) {
          const v = a.dust.clone().applyAxisAngle(new THREE.Vector3(0, 1, 0), b.mesh.rotation.y);
          this.fx.norm.emit(b.x + v.x, v.y, b.z + v.z, rand(-1, 1), rand(0.5, 1.5), rand(-1, 1), 0.6, 0.12, 0.8, 0.65, 0.4, 0.8, 4, 1);
        }
      }

      // produkcja wojska
      if (def.produce) {
        b.productionTimer += dt;
        if (b.productionTimer >= def.interval) {
          b.productionTimer = 0;
          const n = def.produce === 'soldier' ? BARRACKS_MULT[b.upgradeLevel] : 1;
          let made = 0;
          for (let k = 0; k < n; k++) {
            const ang = Math.PI + rand(-1.2, 1.2), r = def.size * 0.5 + 1.5 + Math.random() * 1.5;
            if (this._spawnUnit(def.produce, b.x + Math.cos(ang) * r, b.z + Math.sin(ang) * r)) made++;
          }
          if (made) {
            this.fx.dust(b.x, b.z, 16);
            this.emit('toast', def.produce === 'soldier' ? `🪖 Koszary: +${made} żołnierzy` : '🛡️ Fabryka: nowy czołg!');
          } else this.emit('toast', '⚠️ Limit jednostek osiągnięty');
        }
      }

      // wieże strzelające
      if (def.range) {
        b.recoil = Math.max(0, b.recoil - dt * 4);
        if (a.barrel) a.barrel.position.z = -b.recoil * 0.45;
        if (!b.target || b.target.state === 'dying' || b.target.locked || Math.hypot(b.target.x - b.x, b.target.z - b.z) > def.range) {
          b.target = null;
          let best = -Infinity;
          for (const z of zs) {
            if (z.locked || z.state === 'dying' || z.state === 'rise') continue;
            const d = Math.hypot(z.x - b.x, z.z - b.z);
            if (d < def.range && z.x > best) { best = z.x; b.target = z; }  // "pierwszy w kolejce" do bazy
          }
        }
        b.cooldown -= dt;
        const t = b.target;
        if (b.pendingShot > 0) {
          b.pendingShot -= dt;
          if (b.pendingShot <= 0 && t) this._fireShell(b, t, b.pendingDmg, def);
        }
        if (t) {
          const want = Math.atan2(t.x - b.x, t.z - b.z);
          b.aim = angleLerp(b.aim, want, dt * 6);
          if (a.turret) a.turret.rotation.y = b.aim;
          const err = Math.abs(angDiff(b.aim, want));
          if (b.cooldown <= 0 && err < 0.2) {
            let dmg = def.damage, rate = def.fireRate, dual = false;
            if (b.type === 'cannon') {
              if (b.upgradeLevel >= 1) dual = true;
              if (b.upgradeLevel >= 2) dmg *= 1.2;
              if (b.upgradeLevel >= 3) rate *= 0.8;
            }
            b.cooldown = rate;
            this._fireShell(b, t, dmg, def);
            if (dual) { b.pendingShot = 0.16; b.pendingDmg = dmg; }
          }
        }
      }
    }
  }

  _fireShell(b, t, dmg, def) {
    const big = def.shell === 'big';
    const m = b.muzzle;
    const ca = Math.cos(b.aim), sa = Math.sin(b.aim);
    const mx = b.x + m.x * ca + m.z * sa, mz = b.z - m.x * sa + m.z * ca;
    const my = m.y + (def.slotOnly ? 0.8 : 0);
    const speed = big ? 30 : 24;
    const d = Math.hypot(t.x - mx, t.z - mz);
    const T = Math.max(0.35, d / speed);
    const tx = t.state === 'dying' ? t.x : t.x + (t.vx || 0) * T;
    const tz = t.state === 'dying' ? t.z : t.z + (t.vz || 0) * T;
    b.recoil = 1;
    this.stats.shots++;
    this.fx.muzzle(mx, my, mz, sa, ca);
    this.fx.flash(mx, my, mz, big ? 60 : 30);
    this.audio.cannon(b.x);
    this.fx.shell(mx, my, mz, tx, tz, { speed, big, arc: d * (big ? 0.18 : 0.25) }, (lx, lz) => this._splash(lx, lz, def.splash, dmg, big));
  }

  // ================================================================ GŁÓWNA AKTUALIZACJA
  update(dt) {
    if (this.over || this.paused) return;
    this.stats.time += dt;
    this.gold += this.goldPerSecond * dt;
    this.wood += this.woodPerSecond * dt;
    this.baseFlash = Math.max(0, (this.baseFlash || 0) - dt * 3);

    if (this.completeTimer > 0) {
      this.completeTimer -= dt;
      if (this.completeTimer <= 0) {
        this.completeTimer = -1;
        this.audio.fanfare();
        this.emit('levelComplete', { level: this.level, kills: this.levelKills, reward: this.lastReward });
      }
    }

    this._updateWaves(dt);
    this._updateZombies(dt);
    this._updateBuildings(dt);
    this._updateUnits(dt, this.units, false);
    this._updateUnits(dt, this.tanks, true);
    for (const f of this.world.fires) this.fx.fire(f.x, 1.2, f.z, 0.9);
    for (const p of this.world.torchSpots) this.fx.fire(p.x, p.y, p.z, 0.45);
    if (this.baseHP < this.maxBaseHP * 0.5 && Math.random() < dt * 10) this.fx.smoke(MAP.baseX + rand(-3, 3), 7, rand(-3, 3), 1.5);
    if (this.baseHP < this.maxBaseHP * 0.25 && Math.random() < dt * 15) this.fx.fire(MAP.baseX + rand(-3, 3), 6, rand(-3, 3), 1.2);
  }

  /** Aktualizacja wizualna (także w pauzie) */
  updateVisuals() {
    this.zombieRig.update(this.zombies);
    this.soldierRig.update(this.units);
    this.tankRig.update(this.tanks);
    const bars = this.fx.bars;
    bars.begin();
    for (const z of this.zombies) {
      if (z.state === 'dying' || z.isBoss || z.hp >= z.maxHP) continue;
      bars.push(z.x, 2.45 * z.scale + 0.1, z.z, z.hp / z.maxHP, 0.9 * Math.max(1, z.scale));
    }
    for (const u of this.units) if (u.hp < u.maxHP) bars.push(u.x, 2.2, u.z, u.hp / u.maxHP, 0.8);
    for (const u of this.tanks) if (u.hp < u.maxHP) bars.push(u.x, 2.3, u.z, u.hp / u.maxHP, 1.4);
    for (const b of this.buildings) if (b.hp < b.maxHP) bars.push(b.x, b.size + 1.8, b.z, b.hp / b.maxHP, 1 + b.size * 0.4);
    bars.end();
  }

  // ================================================================ ZAPIS
  save() {
    const data = {
      v: 2, level: this.level, gold: Math.floor(this.gold), wood: Math.floor(this.wood), baseHP: this.baseHP,
      kills: this.kills, difficulty: this.difficultyIndex, stats: this.stats,
      buildings: this.buildings.map(b => ({ type: b.type, x: b.x, z: b.z, hp: b.hp, upgradeLevel: b.upgradeLevel, slot: b.slot, productionTimer: b.productionTimer })),
      units: this.units.map(u => ({ x: u.x, z: u.z, hp: u.hp })),
      tanks: this.tanks.map(u => ({ x: u.x, z: u.z, hp: u.hp })),
    };
    try { localStorage.setItem(SAVE_KEY, JSON.stringify(data)); } catch (e) {}
  }

  static hasSave() {
    try { return !!localStorage.getItem(SAVE_KEY); } catch (e) { return false; }
  }
  static savedInfo() {
    try { const d = JSON.parse(localStorage.getItem(SAVE_KEY)); return d && { level: d.level, difficulty: DIFFICULTY[d.difficulty]?.name }; } catch (e) { return null; }
  }
  static best() { try { return +localStorage.getItem(BEST_KEY) || 0; } catch (e) { return 0; } }

  load() {
    let d;
    try { d = JSON.parse(localStorage.getItem(SAVE_KEY)); } catch (e) { return false; }
    if (!d || d.v !== 2) return false;
    this.reset(d.difficulty ?? 2);
    this.level = d.level; this.gold = d.gold; this.wood = d.wood; this.baseHP = d.baseHP; this.kills = d.kills;
    if (d.stats) this.stats = { ...this.stats, ...d.stats, kinds: { ...this.stats.kinds, ...(d.stats.kinds || {}) } };
    for (const b of d.buildings || []) this._addBuilding(b.type, b.x, b.z, b.slot ?? -1, b);
    for (const u of d.units || []) this._spawnUnit('soldier', u.x, u.z, u);
    for (const u of d.tanks || []) this._spawnUnit('tank', u.x, u.z, u);
    this._updateDifficulty();
    this.zombies.length = 0;
    this.setupLevel();
    return true;
  }
}
