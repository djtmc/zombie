// Efekty: cząstki (krew, gruz, iskry, ogień), smugi pocisków i wyładowania, pogoda.
const FX = { lit: null, glow: null, parts: [], gparts: [], lines: null, segs: [], weather: null };
const NPART = 1400, NGLOW = 1000, NSEG = 600;

function initFx() {
  const geo = new THREE.BoxGeometry(1, 1, 1);
  FX.lit = new THREE.InstancedMesh(geo, new THREE.MeshLambertMaterial(), NPART);
  FX.glow = new THREE.InstancedMesh(geo, new THREE.MeshBasicMaterial({ toneMapped: false }), NGLOW);
  for (const m of [FX.lit, FX.glow]) {
    m.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    m.count = 0; m.frustumCulled = false;
    m.setColorAt(0, new THREE.Color());
    G.scene.add(m);
  }
  FX.lit.castShadow = false;
  const lg = new THREE.BufferGeometry();
  lg.setAttribute('position', new THREE.Float32BufferAttribute(new Float32Array(NSEG * 6), 3));
  lg.setAttribute('color', new THREE.Float32BufferAttribute(new Float32Array(NSEG * 6), 3));
  FX.lines = new THREE.LineSegments(lg, new THREE.LineBasicMaterial({ vertexColors: true, toneMapped: false }));
  FX.lines.frustumCulled = false;
  G.scene.add(FX.lines);
}

// p: {x,y,z, vx,vy,vz, life, size, color, grav, drag, ground:'stick'|'bounce'|null, glow, flat}
function spawnPart(o) {
  const arr = o.glow ? FX.gparts : FX.parts;
  if (arr.length >= (o.glow ? NGLOW : NPART)) arr.shift();
  o.max = o.life; o.c = o.color instanceof THREE.Color ? o.color : new THREE.Color(o.color);
  o.rx = rr(0, 3); o.ry = rr(0, 3); o.spin = o.spin === undefined ? rr(-8, 8) : o.spin;
  o.grav = o.grav === undefined ? 9 : o.grav; o.drag = o.drag || 0;
  arr.push(o);
}

function burst(x, y, z, n, opt) {
  for (let i = 0; i < n; i++) {
    const a = rr(0, TAU), s = rr(opt.spMin || 0.5, opt.sp || 2.5), up = rr(opt.upMin || 0.5, opt.up || 3);
    spawnPart({
      x: x + rr(-0.05, 0.05), y, z: z + rr(-0.05, 0.05), vx: Math.cos(a) * s, vy: up, vz: Math.sin(a) * s,
      life: rr(opt.life * 0.6, opt.life), size: rr(opt.size * 0.6, opt.size), color: Array.isArray(opt.color) ? pick(opt.color) : opt.color,
      grav: opt.grav, drag: opt.drag, ground: opt.ground, glow: opt.glow, flat: opt.flat
    });
  }
}
function blood(x, y, z, n = 8, c = 0x6a0d0a) {
  burst(x, y, z, n, { sp: 2, up: 2.5, life: 0.7, size: 0.07, color: [c, shade(c, 0.7)], ground: 'stick' });
}
function gibs(x, z, c, n = 10) {
  burst(x, 0.5, z, n, { sp: 3, up: 4, life: 1.2, size: 0.12, color: [c, shade(c, 0.7), 0x6a0d0a], ground: 'bounce' });
  for (let i = 0; i < 3; i++) spawnPart({ x: x + rr(-0.3, 0.3), y: 0.02, z: z + rr(-0.3, 0.3), vx: 0, vy: 0, vz: 0, life: 9, size: rr(0.25, 0.45), color: 0x3d0806, grav: 0, flat: true, spin: 0 });
}
function sparks(x, y, z, n = 6, c = 0xffd27a) {
  burst(x, y, z, n, { sp: 3, up: 2.5, life: 0.35, size: 0.05, color: c, glow: true, grav: 6 });
}
function explosion(x, z, r = 1, c = 0xff8a30) {
  burst(x, 0.3, z, 18 + r * 10, { sp: 4 * r, up: 4, life: 0.5, size: 0.14, color: [c, 0xffd27a, 0xff5a20], glow: true, grav: 2, drag: 2 });
  burst(x, 0.2, z, 12, { sp: 3 * r, up: 5, life: 1.4, size: 0.13, color: [0x2a2420, 0x3a332c, 0x55493e], ground: 'bounce' });
  burst(x, 0.4, z, 10, { sp: 1, up: 1.5, life: 1.8, size: 0.35, color: [0x3a3632, 0x26221f], grav: -0.6, drag: 1.2 });
  spawnPart({ x, y: 0.015, z, vx: 0, vy: 0, vz: 0, life: 7, size: r * 0.9, color: 0x14100e, grav: 0, flat: true, spin: 0 });
  flash(c, 10 * r, 5 * r, x, 1.2, z, 0.25);
}
function puff(x, y, z, c, n = 6, size = 0.25) {
  burst(x, y, z, n, { sp: 0.8, up: 1, life: 1.1, size, color: c, grav: -0.4, drag: 1.5 });
}

// Smugi: lista odcinków żyjących ułamek sekundy.
function tracer(x1, y1, z1, x2, y2, z2, c, life = 0.06) { if (FX.segs.length < NSEG) FX.segs.push({ x1, y1, z1, x2, y2, z2, c: new THREE.Color(c), life, max: life }); }
function bolt(x1, y1, z1, x2, y2, z2, c = 0x9fd8ff) {
  let px = x1, py = y1, pz = z1;
  const n = 7;
  for (let i = 1; i <= n; i++) {
    const t = i / n, j = i === n ? 0 : 0.22;
    const nx = lerp(x1, x2, t) + rr(-j, j), ny = lerp(y1, y2, t) + rr(-j, j), nz = lerp(z1, z2, t) + rr(-j, j);
    tracer(px, py, pz, nx, ny, nz, c, 0.12);
    tracer(px, py + 0.02, pz, nx, ny + 0.02, nz, 0xffffff, 0.08);
    px = nx; py = ny; pz = nz;
  }
}

const _m4 = new THREE.Matrix4(), _q = new THREE.Quaternion(), _e = new THREE.Euler(), _v = new THREE.Vector3(), _s = new THREE.Vector3();
function updateParts(arr, mesh, dt) {
  let n = 0;
  for (let i = arr.length - 1; i >= 0; i--) {
    const p = arr[i];
    p.life -= dt;
    if (p.life <= 0) { arr.splice(i, 1); continue; }
    if (!p.rest) {
      p.vy -= p.grav * dt;
      if (p.drag) { const d = Math.exp(-p.drag * dt); p.vx *= d; p.vz *= d; p.vy *= d; }
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      p.rx += p.spin * dt; p.ry += p.spin * 0.7 * dt;
      if (p.y < 0.01 && p.ground) {
        if (p.ground === 'bounce' && p.vy < -1.5) { p.vy *= -0.35; p.vx *= 0.5; p.vz *= 0.5; p.y = 0.01; }
        else { p.y = 0.01; p.rest = true; p.flat = true; p.life = Math.max(p.life, rr(3, 6)); p.max = Math.max(p.max, p.life); }
      }
    }
    const k = p.life / p.max;
    const sz = p.size * (p.glow ? k : p.flat ? Math.min(1, k * 3) : 1);
    if (p.flat) { _e.set(0, p.ry, 0); _s.set(sz, 0.01, sz); }
    else { _e.set(p.rx, p.ry, 0); _s.set(sz, sz, sz); }
    _q.setFromEuler(_e); _v.set(p.x, p.y, p.z);
    _m4.compose(_v, _q, _s);
    mesh.setMatrixAt(n, _m4); mesh.setColorAt(n, p.c);
    n++;
  }
  mesh.count = n;
  mesh.instanceMatrix.needsUpdate = true;
  if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
}

function updateFx(dt) {
  updateParts(FX.parts, FX.lit, dt);
  updateParts(FX.gparts, FX.glow, dt);
  const pa = FX.lines.geometry.attributes.position.array, ca = FX.lines.geometry.attributes.color.array;
  let n = 0;
  for (let i = FX.segs.length - 1; i >= 0; i--) {
    const s = FX.segs[i];
    s.life -= dt;
    if (s.life <= 0) { FX.segs.splice(i, 1); continue; }
    const k = s.life / s.max * 1.6;
    pa.set([s.x1, s.y1, s.z1, s.x2, s.y2, s.z2], n * 6);
    ca.set([s.c.r * k, s.c.g * k, s.c.b * k, s.c.r * k, s.c.g * k, s.c.b * k], n * 6);
    n++;
  }
  FX.lines.geometry.setDrawRange(0, n * 2);
  FX.lines.geometry.attributes.position.needsUpdate = true;
  FX.lines.geometry.attributes.color.needsUpdate = true;
  updateWeather(dt);
}

// ---- pogoda: popiół, śnieg, zarodniki ----
const NW = 900;
function initWeather() {
  const g = new THREE.BufferGeometry();
  const p = new Float32Array(NW * 3);
  for (let i = 0; i < NW; i++) { p[i * 3] = rr(-MW / 2 - 3, MW / 2 + 3); p[i * 3 + 1] = rr(0, 12); p[i * 3 + 2] = rr(-MD / 2 - 3, MD / 2 + 3); }
  g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3));
  FX.weather = new THREE.Points(g, new THREE.PointsMaterial({ size: 0.07, color: 0xffffff, transparent: true, opacity: 0.8, depthWrite: false }));
  FX.weather.frustumCulled = false;
  FX.wkind = 'ash';
  G.scene.add(FX.weather);
}
function setWeather(kind) {
  FX.wkind = kind;
  const m = FX.weather.material;
  if (kind === 'snow') { m.color.set(0xffffff); m.size = 0.09; m.opacity = 0.9; }
  else if (kind === 'ash') { m.color.set(0xff9a5a); m.size = 0.05; m.opacity = 0.75; }
  else { m.color.set(0xb6ff6a); m.size = 0.05; m.opacity = 0.45; }
}
let wTime = 0;
function updateWeather(dt) {
  wTime += dt;
  const p = FX.weather.geometry.attributes.position.array, k = FX.wkind;
  const fall = k === 'snow' ? 1.4 : k === 'ash' ? 0.35 : -0.15;
  for (let i = 0; i < NW; i++) {
    const j = i * 3;
    p[j] += (k === 'snow' ? 0.5 : 0.25) * dt + Math.sin(wTime * 0.8 + i) * 0.2 * dt;
    p[j + 1] -= fall * dt * (0.6 + (i % 7) * 0.08);
    p[j + 2] += Math.cos(wTime * 0.6 + i * 1.3) * 0.15 * dt;
    if (p[j + 1] < 0) p[j + 1] += 12;
    if (p[j + 1] > 12) p[j + 1] -= 12;
    if (p[j] > MW / 2 + 3) p[j] -= MW + 6;
  }
  FX.weather.geometry.attributes.position.needsUpdate = true;
}
