// =====================================================================
//  EFEKTY: cząsteczki (GPU points), krew i ślady wybuchów, pociski,
//  paski zdrowia (billboard instancing), fale uderzeniowe, błyski świateł
// =====================================================================
import * as THREE from 'three';
import { splatTexture, rand } from './utils.js';

// ---------------------------------------------------------------------
class ParticleSystem {
  constructor(scene, capacity, additive) {
    this.cap = capacity;
    this.n = 0;
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(capacity * 3);
    this.col = new Float32Array(capacity * 3);
    this.size = new Float32Array(capacity);
    this.alpha = new Float32Array(capacity);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aColor', new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aAlpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    this.vel = new Float32Array(capacity * 3);
    this.life = new Float32Array(capacity);
    this.maxLife = new Float32Array(capacity);
    this.grav = new Float32Array(capacity);
    this.drag = new Float32Array(capacity);
    this.grow = new Float32Array(capacity);
    this.a0 = new Float32Array(capacity);
    this.uniforms = { uScale: { value: 800 } };
    const mat = new THREE.ShaderMaterial({
      uniforms: this.uniforms,
      transparent: true, depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
      vertexShader: /* glsl */`
        uniform float uScale;
        attribute vec3 aColor; attribute float aSize; attribute float aAlpha;
        varying vec3 vColor; varying float vAlpha;
        void main() {
          vColor = aColor; vAlpha = aAlpha;
          vec4 mv = modelViewMatrix * vec4(position, 1.0);
          gl_PointSize = aSize * uScale / -mv.z;
          gl_Position = projectionMatrix * mv;
        }`,
      fragmentShader: /* glsl */`
        varying vec3 vColor; varying float vAlpha;
        void main() {
          float d = length(gl_PointCoord - 0.5);
          float a = smoothstep(0.5, 0.12, d) * vAlpha;
          if (a < 0.01) discard;
          gl_FragColor = vec4(vColor, a);
          #include <tonemapping_fragment>
          #include <colorspace_fragment>
        }`,
    });
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = additive ? 5 : 4;
    this.geo = g;
    scene.add(this.points);
  }

  emit(x, y, z, vx, vy, vz, life, size, r, g, b, alpha = 1, grav = 0, drag = 0, grow = 0) {
    if (this.n >= this.cap) return;
    const i = this.n++, i3 = i * 3;
    this.pos[i3] = x; this.pos[i3 + 1] = y; this.pos[i3 + 2] = z;
    this.vel[i3] = vx; this.vel[i3 + 1] = vy; this.vel[i3 + 2] = vz;
    this.col[i3] = r; this.col[i3 + 1] = g; this.col[i3 + 2] = b;
    this.life[i] = this.maxLife[i] = life;
    this.size[i] = size; this.alpha[i] = alpha; this.a0[i] = alpha;
    this.grav[i] = grav; this.drag[i] = drag; this.grow[i] = grow;
  }

  update(dt) {
    let n = this.n;
    for (let i = 0; i < n; i++) {
      this.life[i] -= dt;
      if (this.life[i] <= 0) {
        // usuń przez zamianę z ostatnim
        n--;
        if (i !== n) this._copy(n, i);
        i--;
        continue;
      }
      const i3 = i * 3;
      const d = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i3] *= d; this.vel[i3 + 1] = this.vel[i3 + 1] * d - this.grav[i] * dt; this.vel[i3 + 2] *= d;
      this.pos[i3] += this.vel[i3] * dt; this.pos[i3 + 1] += this.vel[i3 + 1] * dt; this.pos[i3 + 2] += this.vel[i3 + 2] * dt;
      if (this.pos[i3 + 1] < 0.03 && this.grav[i] > 0) { this.pos[i3 + 1] = 0.03; this.vel[i3] *= 0.5; this.vel[i3 + 2] *= 0.5; this.vel[i3 + 1] = 0; }
      this.size[i] += this.grow[i] * dt;
      const t = this.life[i] / this.maxLife[i];
      this.alpha[i] = this.a0[i] * Math.min(1, t * 2.5);
    }
    this.n = n;
    this.geo.setDrawRange(0, n);
    for (const k of ['position', 'aColor', 'aSize', 'aAlpha']) {
      const a = this.geo.attributes[k];
      a.needsUpdate = true;
      a.clearUpdateRanges?.();
      a.addUpdateRange?.(0, n * a.itemSize);
    }
  }

  _copy(from, to) {
    const f3 = from * 3, t3 = to * 3;
    for (let k = 0; k < 3; k++) {
      this.pos[t3 + k] = this.pos[f3 + k]; this.vel[t3 + k] = this.vel[f3 + k]; this.col[t3 + k] = this.col[f3 + k];
    }
    this.life[to] = this.life[from]; this.maxLife[to] = this.maxLife[from]; this.size[to] = this.size[from];
    this.alpha[to] = this.alpha[from]; this.a0[to] = this.a0[from]; this.grav[to] = this.grav[from];
    this.drag[to] = this.drag[from]; this.grow[to] = this.grow[from];
  }
}

// ---------------------------------------------------------------------
class Decals {
  constructor(scene, capacity) {
    this.cap = capacity;
    const geo = new THREE.PlaneGeometry(1, 1);
    geo.rotateX(-Math.PI / 2);
    const mat = new THREE.MeshStandardMaterial({
      color: 0xffffff, alphaMap: splatTexture(), transparent: true, depthWrite: false, roughness: 0.35,
      polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2,
    });
    this.mesh = new THREE.InstancedMesh(geo, mat, capacity);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 3), 3);
    this.mesh.count = 0;
    this.mesh.receiveShadow = true;
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 1;
    this.items = [];
    this.next = 0;
    this._m = new THREE.Matrix4(); this._q = new THREE.Quaternion(); this._v = new THREE.Vector3(); this._s = new THREE.Vector3();
    this._axis = new THREE.Vector3(0, 1, 0);
    scene.add(this.mesh);
  }
  add(x, z, size, color) {
    const i = this.next;
    this.next = (this.next + 1) % this.cap;
    this.items[i] = { x, z, size, rot: Math.random() * 6.28, life: 40, age: 0 };
    this.mesh.setColorAt(i, color);
    this.mesh.instanceColor.needsUpdate = true;
    this.mesh.count = Math.max(this.mesh.count, i + 1);
  }
  update(dt) {
    for (let i = 0; i < this.mesh.count; i++) {
      const d = this.items[i];
      if (!d) continue;
      d.age += dt;
      const grow = Math.min(1, d.age * 6);
      const fade = d.age > d.life - 5 ? Math.max(0, (d.life - d.age) / 5) : 1;
      const s = d.size * grow * fade;
      this._q.setFromAxisAngle(this._axis, d.rot);
      this._m.compose(this._v.set(d.x, 0.02 + (i % 10) * 0.001, d.z), this._q, this._s.set(s, 1, s));
      this.mesh.setMatrixAt(i, this._m);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
  }
  clear() { this.items = []; this.mesh.count = 0; this.next = 0; }
}

// ---------------------------------------------------------------------
class HealthBars {
  constructor(scene, capacity) {
    this.cap = capacity;
    const geo = new THREE.PlaneGeometry(1, 1);
    this.hp = new THREE.InstancedBufferAttribute(new Float32Array(capacity), 1);
    this.hp.setUsage(THREE.DynamicDrawUsage);
    geo.setAttribute('aHP', this.hp);
    const mat = new THREE.ShaderMaterial({
      depthTest: false, depthWrite: false, transparent: true,
      vertexShader: /* glsl */`
        attribute float aHP; varying float vHP; varying vec2 vUv; varying float vW;
        void main() {
          vec4 c = modelViewMatrix * vec4(instanceMatrix[3].xyz, 1.0);
          float w = instanceMatrix[0][0];
          c.xy += position.xy * vec2(w, 0.2);
          vUv = uv; vHP = aHP; vW = w;
          gl_Position = projectionMatrix * c;
        }`,
      fragmentShader: /* glsl */`
        varying float vHP; varying vec2 vUv; varying float vW;
        void main() {
          float bx = 0.06 / vW, by = 0.25;
          bool border = vUv.x < bx || vUv.x > 1.0 - bx || vUv.y < by || vUv.y > 1.0 - by;
          vec3 col = vUv.x < vHP ? mix(vec3(0.95, 0.15, 0.1), vec3(0.3, 0.95, 0.3), smoothstep(0.2, 0.7, vHP)) : vec3(0.12, 0.05, 0.05);
          if (border) col = vec3(0.02);
          gl_FragColor = vec4(col, 0.92);
          #include <colorspace_fragment>
        }`,
    });
    this.mesh = new THREE.InstancedMesh(geo, mat, capacity);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 20;
    this.mesh.count = 0;
    this._m = new THREE.Matrix4();
    scene.add(this.mesh);
    this.n = 0;
  }
  begin() { this.n = 0; }
  push(x, y, z, frac, width) {
    if (this.n >= this.cap) return;
    const i = this.n++;
    const m = this._m.makeTranslation(x, y, z);
    m.elements[0] = width;
    this.mesh.setMatrixAt(i, m);
    this.hp.array[i] = frac;
  }
  end() {
    this.mesh.count = this.n;
    this.mesh.instanceMatrix.needsUpdate = true;
    this.hp.needsUpdate = true;
  }
}

// ---------------------------------------------------------------------
export class Effects {
  constructor(scene, quality) {
    this.scene = scene;
    this.density = quality.particles;
    this.add = new ParticleSystem(scene, 3000, true);
    this.norm = new ParticleSystem(scene, 3000, false);
    this.decals = new Decals(scene, 160);
    this.bars = new HealthBars(scene, 500);

    // pociski
    this.tracerMesh = new THREE.InstancedMesh(new THREE.BoxGeometry(0.07, 0.07, 1.4),
      new THREE.MeshBasicMaterial({ color: new THREE.Color(7, 5, 1.5), toneMapped: false }), 300);
    this.tracerMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.tracerMesh.frustumCulled = false;
    this.tracerMesh.count = 0;
    scene.add(this.tracerMesh);
    this.shellMesh = new THREE.InstancedMesh(new THREE.SphereGeometry(0.24, 10, 8),
      new THREE.MeshStandardMaterial({ color: 0x222222, emissive: 0xff5a10, emissiveIntensity: 2.5, roughness: 0.4 }), 120);
    this.shellMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.shellMesh.frustumCulled = false;
    this.shellMesh.castShadow = true;
    this.shellMesh.count = 0;
    scene.add(this.shellMesh);
    this.tracers = [];
    this.shells = [];

    // fale uderzeniowe
    this.rings = [];
    const ringGeo = new THREE.RingGeometry(0.8, 1, 48);
    ringGeo.rotateX(-Math.PI / 2);
    for (let i = 0; i < 8; i++) {
      const r = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: new THREE.Color(1.4, 0.75, 0.3), transparent: true,
        opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending, toneMapped: false }));
      r.visible = false;
      scene.add(r);
      this.rings.push({ mesh: r, t: 1, max: 1 });
    }

    // błyski światła - zawsze w scenie (stała liczba świateł = brak rekompilacji shaderów)
    this.flashes = [0, 1].map(() => {
      const l = new THREE.PointLight(0xff9a40, 0, 18, 2);
      scene.add(l);
      return l;
    });

    this._m = new THREE.Matrix4(); this._q = new THREE.Quaternion(); this._v = new THREE.Vector3();
    this._s = new THREE.Vector3(1, 1, 1); this._fwd = new THREE.Vector3(0, 0, 1); this._dir = new THREE.Vector3();
    this.blood = new THREE.Color(0x5a0505);
    this.greenBlood = new THREE.Color(0x2c4010);
    this.scorch = new THREE.Color(0x141210);
  }

  setQuality(q) { this.density = q.particles; }
  setScale(s) { this.add.uniforms.uScale.value = s; this.norm.uniforms.uScale.value = s; }

  _count(n) { return Math.max(1, Math.round(n * this.density)); }

  // ----------------------------------------------------------- EMITERY
  bloodBurst(x, y, z, amount = 10, dx = 0, dz = 0) {
    const n = this._count(amount);
    for (let i = 0; i < n; i++) {
      const s = rand(2, 6);
      this.norm.emit(x, y, z, dx * s * 0.6 + rand(-2, 2), rand(1.5, 5), dz * s * 0.6 + rand(-2, 2),
        rand(0.5, 1.0), rand(0.12, 0.3), rand(0.3, 0.45), 0.02, 0.02, 1, 14, 0.5);
    }
  }

  splat(x, z, size = 1.4, green = false) {
    this.decals.add(x + rand(-0.3, 0.3), z + rand(-0.3, 0.3), size * rand(0.8, 1.3), green ? this.greenBlood : this.blood);
  }

  muzzle(x, y, z, dx, dz) {
    this.add.emit(x, y, z, dx * 2, 0.3, dz * 2, 0.05, 0.55, 3, 2, 0.6, 0.9);
    for (let i = 0; i < this._count(2); i++) {
      this.add.emit(x, y, z, dx * rand(4, 9) + rand(-1, 1), rand(0, 1.5), dz * rand(4, 9) + rand(-1, 1), rand(0.08, 0.18), 0.15, 5, 3, 1, 1, 6);
    }
    if (Math.random() < 0.5) this.norm.emit(x, y, z, dx * 1.2, 0.6, dz * 1.2, 0.45, 0.25, 0.55, 0.55, 0.55, 0.18, -0.4, 1.5, 0.6);
  }

  sparks(x, y, z, n = 6) {
    for (let i = 0; i < this._count(n); i++) {
      this.add.emit(x, y, z, rand(-4, 4), rand(1, 5), rand(-4, 4), rand(0.2, 0.45), rand(0.08, 0.16), 3.5, 2, 0.6, 1, 12, 1);
    }
  }

  dust(x, z, n = 14, color = [0.45, 0.38, 0.28]) {
    for (let i = 0; i < this._count(n); i++) {
      const a = Math.random() * 6.28, s = rand(1, 3.5);
      this.norm.emit(x + Math.cos(a) * 0.5, 0.2, z + Math.sin(a) * 0.5, Math.cos(a) * s, rand(0.5, 2), Math.sin(a) * s,
        rand(0.6, 1.2), rand(0.5, 0.9), color[0], color[1], color[2], 0.6, 0.5, 2, 1.2);
    }
  }

  explosion(x, z, radius = 2.5, big = false) {
    const k = big ? 1.8 : 1;
    // kula ognia
    for (let i = 0; i < this._count(12 * k); i++) {
      const a = Math.random() * 6.28, el = Math.random() * 1.5, s = rand(2, 7) * k;
      this.add.emit(x, 0.6, z, Math.cos(a) * s * Math.cos(el), Math.sin(el) * s + 2, Math.sin(a) * s * Math.cos(el),
        rand(0.25, 0.5), rand(0.6, 1.1) * k, 2.2, rand(0.7, 1.3), 0.25, 0.55, -1, 3, 1.2);
    }
    // iskry
    this.sparks(x, 0.8, z, 12 * k);
    // dym
    for (let i = 0; i < this._count(12 * k); i++) {
      this.norm.emit(x + rand(-1, 1), rand(0.5, 1.5), z + rand(-1, 1), rand(-1.5, 1.5), rand(1.5, 3.5), rand(-1.5, 1.5),
        rand(1.4, 2.6), rand(1.0, 1.8) * k, 0.16, 0.14, 0.13, 0.55, -0.3, 1.2, 1.6);
    }
    // grudy ziemi
    for (let i = 0; i < this._count(10 * k); i++) {
      this.norm.emit(x, 0.4, z, rand(-5, 5), rand(4, 9), rand(-5, 5), rand(0.8, 1.3), rand(0.15, 0.3), 0.2, 0.16, 0.1, 1, 18, 0.3);
    }
    this.decals.add(x, z, radius * 1.3, this.scorch);
    this.ring(x, z, radius * 1.4, big ? 0.45 : 0.3);
    this.flash(x, 2.5, z, big ? 60 : 28);
  }

  ring(x, z, r, dur) {
    const ring = this.rings.find(r => r.t >= r.max) || this.rings[0];
    ring.t = 0; ring.max = dur; ring.r = r;
    ring.mesh.position.set(x, 0.12, z);
    ring.mesh.visible = true;
  }

  flash(x, y, z, intensity) {
    const l = this.flashes[0].intensity < this.flashes[1].intensity ? this.flashes[0] : this.flashes[1];
    l.position.set(x, y, z);
    l.intensity = Math.max(l.intensity, intensity);
  }

  fire(x, y, z, scale = 1) {
    if (Math.random() > this.density) return;
    this.add.emit(x + rand(-0.25, 0.25) * scale, y, z + rand(-0.25, 0.25) * scale, rand(-0.3, 0.3), rand(1.5, 3) * scale, rand(-0.3, 0.3),
      rand(0.35, 0.7), rand(0.4, 0.7) * scale, 2.6, rand(0.8, 1.3), 0.2, 0.8, -0.5, 1, -0.6);
    if (Math.random() < 0.35) {
      this.norm.emit(x, y + 0.9 * scale, z, rand(-0.3, 0.3), rand(1, 2), rand(-0.3, 0.3), rand(1.5, 2.5), rand(0.5, 0.9) * scale,
        0.12, 0.11, 0.1, 0.4, -0.2, 0.5, 0.9);
    }
  }

  smoke(x, y, z, scale = 1) {
    this.norm.emit(x, y, z, rand(-0.3, 0.3), rand(0.8, 1.6), rand(-0.3, 0.3), rand(2, 3.2), rand(0.5, 0.8) * scale,
      0.35, 0.34, 0.33, 0.45, -0.1, 0.4, 0.9);
  }

  magic(x, y, z) {
    this.add.emit(x + rand(-3, 3), y, z + rand(-5, 5), rand(-0.3, 0.3), rand(0.6, 1.6), rand(-0.3, 0.3), rand(1, 2), rand(0.15, 0.3), 1.6, 0.5, 3, 1, -0.2, 0.2);
  }

  heal(x, z) {
    for (let i = 0; i < this._count(16); i++) {
      this.add.emit(x + rand(-1.5, 1.5), rand(0.2, 2), z + rand(-1.5, 1.5), 0, rand(1, 2.5), 0, rand(0.6, 1.1), rand(0.2, 0.35), 0.5, 3, 0.8, 1);
    }
  }

  // ----------------------------------------------------------- POCISKI
  tracer(fx, fy, fz, tx, ty, tz, onArrive) {
    const dx = tx - fx, dy = ty - fy, dz = tz - fz;
    const len = Math.hypot(dx, dy, dz) || 1;
    this.tracers.push({ x: fx, y: fy, z: fz, dx: dx / len, dy: dy / len, dz: dz / len, left: len, onArrive });
  }

  /** Pocisk balistyczny lecący łukiem; onLand(x,z) wywołane przy uderzeniu w ziemię */
  shell(fx, fy, fz, tx, tz, opts, onLand) {
    const d = Math.hypot(tx - fx, tz - fz);
    const T = Math.max(0.35, d / (opts.speed || 30));
    this.shells.push({ fx, fy, fz, tx, tz, t: 0, T, h: opts.arc ?? d * 0.22, big: !!opts.big, onLand, x: fx, y: fy, z: fz });
  }

  // ----------------------------------------------------------- AKTUALIZACJA
  update(dt) {
    const m = this._m, q = this._q, v = this._v;

    // smugi pocisków
    let n = 0;
    for (let i = this.tracers.length - 1; i >= 0; i--) {
      const t = this.tracers[i];
      const step = 120 * dt;
      t.x += t.dx * step; t.y += t.dy * step; t.z += t.dz * step; t.left -= step;
      if (t.left <= 0) { t.onArrive?.(); this.tracers.splice(i, 1); continue; }
    }
    for (const t of this.tracers) {
      if (n >= 300) break;
      q.setFromUnitVectors(this._fwd, this._dir.set(t.dx, t.dy, t.dz));
      m.compose(v.set(t.x, t.y, t.z), q, this._s.set(1, 1, Math.min(1, t.left / 1.4 + 0.2)));
      this.tracerMesh.setMatrixAt(n++, m);
    }
    this.tracerMesh.count = n;
    this.tracerMesh.instanceMatrix.needsUpdate = true;

    // pociski armatnie
    n = 0;
    for (let i = this.shells.length - 1; i >= 0; i--) {
      const s = this.shells[i];
      s.t += dt;
      const k = Math.min(1, s.t / s.T);
      s.x = s.fx + (s.tx - s.fx) * k;
      s.z = s.fz + (s.tz - s.fz) * k;
      s.y = s.fy * (1 - k) + 4 * s.h * k * (1 - k);
      if (Math.random() < this.density) {
        this.norm.emit(s.x, s.y, s.z, rand(-0.2, 0.2), rand(0.2, 0.6), rand(-0.2, 0.2), rand(0.3, 0.6), s.big ? 0.55 : 0.3, 0.45, 0.42, 0.4, 0.3, -0.3, 1, 0.8);
        this.add.emit(s.x, s.y, s.z, 0, 0, 0, 0.12, s.big ? 0.6 : 0.4, 2.5, 1, 0.25, 0.7);
      }
      if (k >= 1) { s.onLand?.(s.tx, s.tz); this.shells.splice(i, 1); }
    }
    for (const s of this.shells) {
      if (n >= 120) break;
      m.compose(v.set(s.x, s.y, s.z), q.identity(), this._s.setScalar(s.big ? 1.8 : 1));
      this.shellMesh.setMatrixAt(n++, m);
    }
    this.shellMesh.count = n;
    this.shellMesh.instanceMatrix.needsUpdate = true;

    for (const r of this.rings) {
      if (r.t >= r.max) { r.mesh.visible = false; continue; }
      r.t += dt;
      const k = Math.min(1, r.t / r.max);
      r.mesh.scale.setScalar(0.3 + r.r * (1 - (1 - k) * (1 - k)));
      r.mesh.material.opacity = (1 - k) * 0.45;
    }
    for (const l of this.flashes) l.intensity = Math.max(0, l.intensity - dt * 400);

    this.add.update(dt);
    this.norm.update(dt);
    this.decals.update(dt);
  }

  clear() {
    this.tracers.length = 0;
    this.shells.length = 0;
    this.decals.clear();
  }
}
