// Prostokątna plansza (MW x MD pól): droga od lewej krawędzi do fortecy po prawej,
// pola pod wieże wzdłuż drogi, rekwizyty biomu i animacja rozpadu / składania planszy.
const MW = 30, MD = 14;
const wx = cx => cx - MW / 2 + 0.5;
const wz = cz => cz - MD / 2 + 0.5;
const cellKey = (cx, cz) => cz * MW + cx;

const MAP = {
  biome: null, biomeIndex: 0, road: new Set(), path: [], segLen: [], pathLen: 0,
  pads: [], fort: null, root: null, tiles: null, cols: [], tileInfo: [],
  state: 'none', t: 0, onBuilt: null, onFallen: null, poolCells: new Set()
};

function genRoad() {
  const cells = [];
  let x = 0, z = ri(2, MD - 3);
  cells.push([x, z]);
  const endX = MW - 6;
  while (x < endX) {
    const len = ri(2, 5);
    for (let i = 0; i < len && x < endX; i++) { x++; cells.push([x, z]); }
    if (x >= endX) break;
    let nz, guard = 0;
    do { nz = ri(1, MD - 2); } while (Math.abs(nz - z) < 3 && guard++ < 50);
    const st = Math.sign(nz - z);
    while (z !== nz) { z += st; cells.push([x, z]); }
  }
  const zEnd = clamp(z, 3, MD - 4);
  if (zEnd !== z) { x++; cells.push([x, z]); const st = Math.sign(zEnd - z); while (z !== zEnd) { z += st; cells.push([x, z]); } }
  while (x < MW - 5) { x++; cells.push([x, z]); }
  return cells;
}

function buildPath(cells) {
  const pts = [[wx(-2), wz(cells[0][1])]];
  for (let i = 0; i < cells.length; i++) {
    const p = cells[i], a = cells[i - 1], b = cells[i + 1];
    if (!a || !b || (a[0] - p[0]) !== (p[0] - b[0]) || (a[1] - p[1]) !== (p[1] - b[1])) pts.push([wx(p[0]), wz(p[1])]);
  }
  const last = cells[cells.length - 1];
  pts.push([wx(last[0] + 2), wz(last[1])]);
  MAP.path = pts.map(p => ({ x: p[0], z: p[1] }));
  MAP.segLen = []; MAP.pathLen = 0;
  for (let i = 1; i < pts.length; i++) {
    const l = Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
    MAP.segLen.push(l); MAP.pathLen += l;
  }
}
// Pozycja na drodze po przejściu dystansu s (out: {x, z, dx, dz}).
function pathAt(s, out) {
  let i = 0;
  while (i < MAP.segLen.length - 1 && s > MAP.segLen[i]) { s -= MAP.segLen[i]; i++; }
  const a = MAP.path[i], b = MAP.path[i + 1], l = MAP.segLen[i] || 1;
  const t = clamp(s / l, 0, 1);
  out.x = a.x + (b.x - a.x) * t; out.z = a.z + (b.z - a.z) * t;
  out.dx = (b.x - a.x) / l; out.dz = (b.z - a.z) / l;
  return out;
}

function pickPads(cells) {
  const fortZ = cells[cells.length - 1][1];
  const inFort = (cx, cz) => cx >= MW - 4 && Math.abs(cz - fortZ) <= 2;
  const cands = [];
  for (let cz = 0; cz < MD; cz++) for (let cx = 1; cx < MW - 1; cx++) {
    if (MAP.road.has(cellKey(cx, cz)) || inFort(cx, cz)) continue;
    let adj = false, score = 0;
    for (let dz = -3; dz <= 3; dz++) for (let dx = -3; dx <= 3; dx++) {
      if (!MAP.road.has(cellKey(cx + dx, cz + dz)) || cx + dx < 0 || cx + dx >= MW) continue;
      const d = Math.hypot(dx, dz);
      if (Math.max(Math.abs(dx), Math.abs(dz)) === 1) adj = true;
      if (d <= 3) score += 1;
    }
    if (adj) cands.push({ cx, cz, score: score + rnd() * 1.5 });
  }
  cands.sort((a, b) => b.score - a.score);
  const pads = [];
  for (const c of cands) {
    if (pads.length >= 16) break;
    if (pads.some(p => Math.max(Math.abs(p.cx - c.cx), Math.abs(p.cz - c.cz)) < 2)) continue;
    pads.push({ cx: c.cx, cz: c.cz, x: wx(c.cx), z: wz(c.cz), tower: null, id: pads.length });
  }
  return { pads, fortZ, inFort };
}

function buildFortress(biome, gx, gz) {
  const b = new Builder(), g = new Builder();
  const stone = biome.key === 'winter' ? 0x8a8f99 : biome.key === 'swamp' ? 0x5f6250 : 0x6e655c;
  const dark = shade(stone, 0.7), wood = 0x5a3e28;
  // mury: prostokąt 3.6 x 4.6 z bramą od strony drogi (-x)
  const W2 = 1.8, D2 = 2.3, h = 0.9;
  b.box(0.3, h, D2 * 2, stone, -W2, 0, 0);
  b.box(0.3, h, D2 * 2, stone, W2, 0, 0);
  b.box(W2 * 2, h, 0.3, stone, 0, 0, -D2);
  b.box(W2 * 2, h, 0.3, stone, 0, 0, D2);
  for (let i = -4; i <= 4; i++) { b.box(0.14, 0.16, 0.12, dark, -W2, h, i * 0.5); b.box(0.12, 0.16, 0.14, dark, i * 0.4, h, -D2); b.box(0.12, 0.16, 0.14, dark, i * 0.4, h, D2); }
  b.box(0.34, 0.55, 0.8, 0x2a1c12, -W2 - 0.02, 0, 0); // brama
  b.box(0.36, 0.08, 0.86, wood, -W2 - 0.02, 0.55, 0);
  for (const [x, z] of [[-W2, -D2], [W2, -D2], [-W2, D2], [W2, D2]]) {
    b.cyl(0.36, 0.42, 1.4, stone, x, 0, z, 8);
    b.cone(0.48, 0.55, 0x6a2a22, x, 1.4, z, 8);
  }
  // twierdza z wieżą sygnałową
  b.box(1.6, 1.3, 1.9, shade(stone, 0.92), 0.3, 0, 0);
  b.box(1.75, 0.12, 2.05, dark, 0.3, 1.3, 0);
  b.cyl(0.38, 0.45, 1.1, stone, 0.3, 1.42, 0, 8);
  b.box(0.06, 0.6, 0.06, 0x2a2a2a, 0.3, 2.52, 0);
  b.box(0.36, 0.22, 0.02, 0x8a1a1a, 0.48, 2.85, 0);
  g.ball(0.17, 0xffd27a, 0.3, 2.62, 0, 1);
  // worki z piaskiem i skrzynie przed bramą
  for (let i = 0; i < 5; i++) b.box(0.28, 0.14, 0.16, 0x8a7a55, -W2 - 0.45, 0, -0.9 + (i > 2 ? 1.5 : 0) + (i % 3) * 0.18 - 0.1);
  b.box(0.3, 0.3, 0.3, wood, W2 - 0.5, 0, D2 - 0.5);
  const grp = new THREE.Group();
  grp.add(b.mesh(), g.mesh(MAT.glow, false));
  grp.position.set(gx, 0, gz);
  return grp;
}

function buildMap(biomeIndex) {
  MAP.biomeIndex = biomeIndex;
  if (typeof COV !== 'undefined') COV.clear();
  const biome = MAP.biome = BIOMES[biomeIndex % BIOMES.length];
  MAP.road = new Set();
  const cells = genRoad();
  for (const c of cells) MAP.road.add(cellKey(c[0], c[1]));
  buildPath(cells);
  const pp = pickPads(cells);
  MAP.pads = pp.pads;
  const padSet = new Set(MAP.pads.map(p => cellKey(p.cx, p.cz)));
  MAP.fort = { x: wx(MW - 2) - 0.5, z: wz(pp.fortZ), cz: pp.fortZ, hp: 0 };

  const root = new THREE.Group();
  MAP.root = root;
  G.scene.add(root);

  // płytki terenu jako jeden InstancedMesh (każda płytka spada osobno przy rozpadzie)
  const tileGeo = new THREE.BoxGeometry(1, 2, 1);
  const tiles = new THREE.InstancedMesh(tileGeo, new THREE.MeshLambertMaterial({ flatShading: true }), MW * MD);
  tiles.receiveShadow = true; tiles.castShadow = false;
  MAP.tileInfo = [];
  const m4 = new THREE.Matrix4();
  for (let cz = 0; cz < MD; cz++) for (let cx = 0; cx < MW; cx++) {
    const i = cellKey(cx, cz);
    const road = MAP.road.has(i);
    const top = road ? -0.06 : rr(-0.02, 0.04);
    MAP.tileInfo[i] = { top, delay: rr(0, 0.25), spin: rr(-1, 1) };
    m4.makeTranslation(wx(cx), top - 1, wz(cz));
    tiles.setMatrixAt(i, m4);
    let c = road ? shade(biome.road, rr(0.92, 1.06)) : shade(pick(biome.ground), rr(0.9, 1.08));
    if (!road && (cx === 0 || cx === MW - 1 || cz === 0 || cz === MD - 1)) c.multiplyScalar(0.9);
    tiles.setColorAt(i, c);
  }
  root.add(tiles);
  MAP.tiles = tiles;

  // kolumny z rekwizytami: każda kolumna to jeden model (rozpad przesuwa się kolumnami)
  MAP.cols = [];
  MAP.poolCells = new Set();
  const lights = [];
  for (let cx = 0; cx < MW; cx++) {
    const b = new Builder(), g = new Builder();
    for (let cz = 0; cz < MD; cz++) {
      const k = cellKey(cx, cz), x = wx(cx), z = wz(cz);
      if (MAP.road.has(k)) {
        if (biome.key !== 'swamp' && cz % 1 === 0 && MAP.road.has(cellKey(cx + 1, cz)) && MAP.road.has(cellKey(cx - 1, cz)) && cx % 2 === 0)
          b.box(0.34, 0.01, 0.06, biome.roadLine, x, -0.06, z);
        if (chance(0.06)) b.box(rr(0.15, 0.3), 0.012, rr(0.15, 0.3), 0x3a0e0a, x + rr(-0.3, 0.3), -0.06, z + rr(-0.3, 0.3));
        continue;
      }
      if (padSet.has(k)) {
        b.box(0.88, 0.1, 0.88, shade(biome.pad, 1.25), x, 0, z);
        b.box(0.74, 0.02, 0.74, shade(biome.pad, 0.8), x, 0.1, z);
        for (const [ox, oz] of [[-0.3, -0.3], [0.3, -0.3], [-0.3, 0.3], [0.3, 0.3]]) b.box(0.06, 0.03, 0.06, 0xe8d8a0, x + ox, 0.1, z + oz);
        continue;
      }
      if (pp.inFort(cx, cz)) continue;
      let near = false;
      for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) if (MAP.road.has(cellKey(cx + dx, cz + dz))) near = true;
      const o = decorateCell(biome, b, g, x, z, near);
      if (o.pool) MAP.poolCells.add(k);
      if (o.light && lights.length < 3) lights.push(o.light);
    }
    const grp = new THREE.Group();
    if (b.pos.length) grp.add(b.mesh());
    if (g.pos.length) grp.add(g.mesh(MAT.glow, false));
    if (cx === MW - 2) grp.add(buildFortress(biome, MAP.fort.x, MAP.fort.z));
    root.add(grp);
    MAP.cols.push(grp);
  }
  MAP.lights = lights;
  applyBiomeLook(biome);
  MAP.state = 'build'; MAP.t = 0;
  layoutAnim(0);
}

function applyBiomeLook(b) {
  G.scene.background = col(b.fog);
  G.scene.fog.color.set(b.fog); G.scene.fog.near = b.fogNear; G.scene.fog.far = b.fogFar;
  G.hemi.color.set(b.hemiSky); G.hemi.groundColor.set(b.hemiGround); G.hemi.intensity = b.hemiI;
  G.sun.color.set(b.sun); G.sun.intensity = b.sunI;
  G.sun.position.set(b.sunPos[0], b.sunPos[1], b.sunPos[2]); G.sun.target.position.set(0, 0, 0);
  const u = POST.mat.uniforms;
  u.uTint.value.set(...b.tint); u.uLift.value.set(...b.lift); u.uExposure.value = b.exposure;
}

function lightMapDecor() {
  claimLight('fort', 0xffc070, 4, 7, MAP.fort.x + 0.3, 2.9, MAP.fort.z, 0.2);
  for (const l of MAP.lights) claimLight('map', l[0], l[1], l[2], l[3], l[4], l[5], 0.35);
}

// Animacja: 'build' = płytki wynurzają się z mroku od fortecy w lewo, 'crumble' = spadają od lewej.
function layoutAnim(dt) {
  if (MAP.state !== 'build' && MAP.state !== 'crumble') return;
  MAP.t += dt;
  const t = MAP.t, m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), e = new THREE.Euler(), v = new THREE.Vector3(), one = new THREE.Vector3(1, 1, 1);
  let done = true;
  for (let cx = 0; cx < MW; cx++) {
    let off, rot = 0;
    if (MAP.state === 'build') {
      const k = clamp((t - (MW - 1 - cx) * 0.05) / 0.9, 0, 1);
      off = -24 * Math.pow(1 - smooth(k), 2);
      if (k < 1) done = false;
    } else {
      const k = Math.max(0, t - cx * 0.06);
      off = -k * k * 14; rot = k * 0.5;
      if (off > -40) done = false;
    }
    MAP.cols[cx].position.y = off;
    for (let cz = 0; cz < MD; cz++) {
      const i = cellKey(cx, cz), info = MAP.tileInfo[i];
      let o = off, r = rot;
      if (MAP.state === 'crumble') { const k = Math.max(0, t - cx * 0.06 - info.delay); o = -k * k * 14; r = k * info.spin; }
      e.set(r * 0.6, 0, r);
      q.setFromEuler(e);
      v.set(wx(cx), info.top - 1 + o, wz(cz));
      m4.compose(v, q, one);
      MAP.tiles.setMatrixAt(i, m4);
    }
  }
  MAP.tiles.instanceMatrix.needsUpdate = true;
  if (done) {
    if (MAP.state === 'build') {
      MAP.state = 'live';
      for (const c of MAP.cols) c.position.y = 0;
      lightMapDecor();
      if (MAP.onBuilt) MAP.onBuilt();
    } else {
      MAP.state = 'none';
      disposeMap();
      if (MAP.onFallen) MAP.onFallen();
    }
  }
}

function crumbleMap() {
  releaseLights('map'); releaseLights('fort');
  MAP.state = 'crumble'; MAP.t = 0;
}
function disposeMap() {
  if (!MAP.root) return;
  MAP.root.traverse(o => { if (o.geometry) o.geometry.dispose(); });
  G.scene.remove(MAP.root);
  MAP.root = null;
}
function nearestPad(x, z, maxD = 0.75) {
  let best = null, bd = maxD * maxD;
  for (const p of MAP.pads) { const d = dist2(p.x, p.z, x, z); if (d < bd) { bd = d; best = p; } }
  return best;
}
