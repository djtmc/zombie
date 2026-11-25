// Grafika: renderer, scena, kamera, światła i budowanie modeli z prostopadłościanów.
const G = {
  renderer: null, scene: null, camera: null, sun: null, hemi: null,
  lights: [], W: 1, H: 1, pixel: 1
};

// Wspólny materiał z kolorami wierzchołków - całe modele składamy z pudełek w jedną geometrię.
const MAT = {};
function makeMaterials() {
  MAT.v = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
  MAT.glow = new THREE.MeshBasicMaterial({ vertexColors: true });
  MAT.water = new THREE.MeshStandardMaterial({ color: 0x334, roughness: 0.25, metalness: 0.1, transparent: true, opacity: 0.85 });
}

// Budowniczy: zbiera pudełka/kształty z kolorami i skleja je w jedną BufferGeometry.
class Builder {
  constructor() { this.pos = []; this.nor = []; this.col = []; }
  add(geo, color, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
    const g = geo.index ? geo.toNonIndexed() : geo;
    const m = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z),
      new THREE.Quaternion().setFromEuler(new THREE.Euler(rx, ry, rz)), new THREE.Vector3(sx, sy, sz));
    g.applyMatrix4(m);
    const p = g.attributes.position.array, n = g.attributes.normal.array;
    const c = color instanceof THREE.Color ? color : new THREE.Color(color);
    for (let i = 0; i < p.length; i++) { this.pos.push(p[i]); this.nor.push(n[i]); }
    for (let i = 0; i < p.length / 3; i++) this.col.push(c.r, c.g, c.b);
    return this;
  }
  box(w, h, d, color, x = 0, y = 0, z = 0, ry = 0, rx = 0, rz = 0) {
    return this.add(new THREE.BoxGeometry(w, h, d), color, x, y + h / 2, z, rx, ry, rz);
  }
  cyl(rt, rb, h, color, x = 0, y = 0, z = 0, seg = 6, rx = 0, rz = 0) {
    return this.add(new THREE.CylinderGeometry(rt, rb, h, seg), color, x, y + h / 2, z, rx, 0, rz);
  }
  cone(r, h, color, x = 0, y = 0, z = 0, seg = 6) {
    return this.add(new THREE.ConeGeometry(r, h, seg), color, x, y + h / 2, z);
  }
  ball(r, color, x = 0, y = 0, z = 0, det = 0, sx = 1, sy = 1, sz = 1) {
    return this.add(new THREE.IcosahedronGeometry(r, det), color, x, y, z, 0, 0, 0, sx, sy, sz);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    g.computeBoundingSphere();
    return g;
  }
  mesh(mat = MAT.v, shadow = true) {
    const m = new THREE.Mesh(this.geometry(), mat);
    m.castShadow = shadow; m.receiveShadow = true;
    return m;
  }
}

// Pula świateł punktowych o stałej liczbie (bez przebudowy shaderów przy zmianie liczby świateł).
const NLIGHTS = 8;
function initLights() {
  for (let i = 0; i < NLIGHTS; i++) {
    const l = new THREE.PointLight(0xffaa55, 0, 6, 1.6);
    l.position.set(0, -50, 0);
    G.scene.add(l);
    G.lights.push({ l, owner: null, t: 0, life: 0, base: 0, flick: 0, on: true });
  }
}
// Stałe światło (np. beczka z ogniem) - migocze, dopóki nie zostanie zwolnione.
function claimLight(owner, color, intensity, range, x, y, z, flick = 0.25) {
  const s = G.lights.find(s => s.on && !s.owner);
  if (!s) return null;
  s.owner = owner; s.life = 0; s.base = intensity; s.flick = flick;
  s.l.color.set(color); s.l.distance = range; s.l.intensity = intensity; s.l.position.set(x, y, z);
  return s;
}
function releaseLights(owner) { for (const s of G.lights) if (s.owner === owner) { s.owner = null; s.l.intensity = 0; s.l.position.y = -50; } }
// Krótki błysk (wystrzał, wybuch) - zajmuje najstarszy wolny lub wygasający slot.
function flash(color, intensity, range, x, y, z, life = 0.12) {
  let s = G.lights.find(s => s.on && !s.owner);
  if (!s) s = G.lights.filter(s => s.on && s.owner === 'flash').sort((a, b) => a.t - b.t)[0];
  if (!s) return;
  s.owner = 'flash'; s.life = life; s.t = life; s.base = intensity; s.flick = 0;
  s.l.color.set(color); s.l.distance = range; s.l.intensity = intensity; s.l.position.set(x, y, z);
}
function updateLights(dt, time) {
  for (const s of G.lights) {
    if (!s.owner) continue;
    if (s.owner === 'flash') {
      s.t -= dt;
      if (s.t <= 0) { s.owner = null; s.l.intensity = 0; s.l.position.y = -50; }
      else s.l.intensity = s.base * (s.t / s.life);
    } else if (s.flick) {
      s.l.intensity = s.base * (1 - s.flick + s.flick * (0.6 + 0.4 * Math.sin(time * 13 + s.l.position.x * 7) * Math.sin(time * 7.3 + s.l.position.z)));
    }
  }
}

function initGfx() {
  const r = new THREE.WebGLRenderer({ antialias: false, powerPreference: 'high-performance' });
  r.setPixelRatio(1);
  r.shadowMap.enabled = true;
  r.shadowMap.type = THREE.PCFShadowMap;
  r.shadowMap.autoUpdate = false;
  r.outputColorSpace = THREE.SRGBColorSpace;
  r.toneMapping = THREE.ACESFilmicToneMapping;
  r.toneMappingExposure = 1.05;
  document.body.prepend(r.domElement);
  G.renderer = r;
  G.scene = new THREE.Scene();
  G.camera = new THREE.PerspectiveCamera(30, 1, 0.5, 200);
  G.hemi = new THREE.HemisphereLight(0x8899bb, 0x221a14, 0.6);
  G.scene.add(G.hemi);
  const sun = new THREE.DirectionalLight(0xffeedd, 1.4);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  const sc = sun.shadow.camera;
  sc.left = -22; sc.right = 22; sc.top = 14; sc.bottom = -14; sc.near = 1; sc.far = 80;
  sun.shadow.bias = -0.0008; sun.shadow.normalBias = 0.02;
  G.scene.add(sun); G.scene.add(sun.target);
  G.sun = sun;
  G.scene.fog = new THREE.Fog(0x000000, 40, 90);
  makeMaterials();
  initLights();
}
