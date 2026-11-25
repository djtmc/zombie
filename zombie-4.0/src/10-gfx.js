// Grafika: renderer, scena, kamera, światła i budowanie modeli z prostopadłościanów.
const G = {
  renderer: null, scene: null, camera: null, sun: null, hemi: null,
  lights: [], W: 1, H: 1, pixel: 1
};

// Wspólne uniformy shaderów (czas, wiatr, śnieg, faktura powierzchni).
const GU = { uTime: { value: 0 }, uWind: { value: 1 }, uSnow: { value: 0 }, uSnowCol: { value: new THREE.Color(0xeef3fa) } };

// Szum i wypukłość liczone w shaderze - faktura powierzchni bez plików graficznych.
const GLSL_NOISE = `
float zH(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float zN(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(zH(i), zH(i + vec2(1.0, 0.0)), f.x), mix(zH(i + vec2(0.0, 1.0)), zH(i + vec2(1.0, 1.0)), f.x), f.y); }
vec3 zBump(vec3 P, vec3 N, float dBx, float dBy, float sc) {
  vec3 dPdx = dFdx(P), dPdy = dFdy(P);
  vec3 R1 = cross(dPdy, N), R2 = cross(N, dPdx);
  float det = dot(dPdx, R1);
  vec3 grad = sign(det) * (dBx * R1 + dBy * R2);
  return normalize(abs(det) * N - sc * grad);
}`;

// Materiał świata: kolory wierzchołków + (wg jakości) faktura, śnieg na powierzchniach od góry, kołysanie roślin.
function worldMaterial(opts = {}) {
  const mat = new THREE.MeshLambertMaterial(Object.assign({ vertexColors: true, flatShading: true }, opts.params || {}));
  mat.userData.noSnow = !!opts.noSnow;
  mat.customProgramCacheKey = () => 'zw' + (mat.defines && mat.defines.Z_DETAIL !== undefined ? 'd' : '') + (opts.noSnow ? 'n' : '');
  mat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, GU);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aSway; uniform float uTime; uniform float uWind; varying vec3 vWP;')
      .replace('#include <begin_vertex>', `#include <begin_vertex>
if (aSway > 0.0) {
  vec4 wp0 = modelMatrix * vec4(position, 1.0);
  float ph = uTime * 1.7 + wp0.x * 0.9 + wp0.z * 0.7;
  transformed.x += (sin(ph) * 0.6 + sin(ph * 2.3 + 1.7) * 0.4) * 0.05 * aSway * uWind;
  transformed.z += cos(ph * 0.8) * 0.04 * aSway * uWind;
}`)
      .replace('#include <project_vertex>', '#include <project_vertex>\nvWP = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uSnow; uniform vec3 uSnowCol; varying vec3 vWP;' + GLSL_NOISE)
      .replace('#include <color_fragment>', `#include <color_fragment>
float zG = 0.5;
#ifdef Z_DETAIL
  vec3 zWN = normalize(cross(dFdx(vWP), dFdy(vWP)));
  vec2 zUV = abs(zWN.y) > 0.6 ? vWP.xz : (abs(zWN.x) > abs(zWN.z) ? vWP.zy : vWP.xy);
  zG = zN(zUV * 4.0) * 0.65 + zN(zUV * 9.0) * 0.35;
  float zCr = smoothstep(0.025, 0.0, abs(zN(zUV * 1.7 + 7.0) - 0.5));
  diffuseColor.rgb *= 0.92 + 0.16 * zG - zCr * 0.15;
#endif
${opts.noSnow ? '' : `if (uSnow > 0.0) {
  float zn = zN(vWP.xz * 2.3);
  float zUp = normalize(cross(dFdx(vWP), dFdy(vWP))).y;
  float cv = smoothstep(0.5, 0.78, zUp + (zn - 0.5) * 0.5) * uSnow;
  diffuseColor.rgb = mix(diffuseColor.rgb, uSnowCol * (0.9 + 0.15 * zn), cv);
}`}`)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
#ifdef Z_DETAIL
  normal = zBump(-vViewPosition, normal, dFdx(zG), dFdy(zG), 0.35);
#endif`);
  };
  return mat;
}
function setDetail(mat, on) {
  mat.defines = mat.defines || {};
  const had = mat.defines.Z_DETAIL !== undefined;
  if (on === had) return;
  if (on) mat.defines.Z_DETAIL = ''; else delete mat.defines.Z_DETAIL;
  mat.needsUpdate = true;
}

// Materiał instancjonowanych postaci: mignięcie przy trafieniu (atrybut aFlash na instancję).
function instMaterial() {
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
  mat.customProgramCacheKey = () => 'zinst';
  mat.onBeforeCompile = sh => {
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nattribute float aFlash; varying float vFlash;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFlash = aFlash;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nvarying float vFlash;')
      .replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\ntotalEmissiveRadiance += vec3(1.0, 0.85, 0.6) * vFlash * 0.9;');
  };
  return mat;
}

// Woda: kałuże w mieście, lód w zimie, toksyny na bagnie - animowane w shaderze.
function waterMaterial() {
  const mat = new THREE.MeshBasicMaterial({ vertexColors: true });
  mat.userData.u = { uWMode: { value: 0 } };
  mat.customProgramCacheKey = () => 'zwater';
  mat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, GU, mat.userData.u);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vWP;')
      .replace('#include <project_vertex>', '#include <project_vertex>\nvWP = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', '#include <common>\nuniform float uTime; uniform float uWMode; varying vec3 vWP;' + GLSL_NOISE)
      .replace('#include <color_fragment>', `#include <color_fragment>
vec2 p = vWP.xz;
if (uWMode < 0.5) {
  float r = zN(p * 6.0 + vec2(uTime * 0.4, uTime * 0.25)) * 0.6 + zN(p * 13.0 - uTime * 0.6) * 0.4;
  diffuseColor.rgb *= 0.7 + 0.5 * r;
  diffuseColor.rgb += vec3(1.0, 0.55, 0.25) * pow(r, 6.0) * 0.6;
} else if (uWMode < 1.5) {
  float n1 = zN(p * 3.0), ck = smoothstep(0.035, 0.0, abs(zN(p * 5.0 + 40.0) - 0.5)) + smoothstep(0.03, 0.0, abs(zN(p * 2.4 + 71.0) - 0.48));
  diffuseColor.rgb = mix(diffuseColor.rgb * (0.8 + 0.4 * n1), vec3(0.95, 0.98, 1.0), clamp(ck * 0.8, 0.0, 1.0));
  diffuseColor.rgb += vec3(0.3, 0.35, 0.4) * pow(zN(p * 1.5 + uTime * 0.05), 4.0);
} else {
  float t = uTime;
  float c1 = zN(p * 2.4 + vec2(0.0, t * 0.3)), c2 = zN(p * 5.5 - vec2(t * 0.4, 0.0));
  float band = 1.0 - abs(2.0 * c1 - 1.0);
  float bub = smoothstep(0.82, 0.95, zN(p * 11.0 + t * 0.7));
  diffuseColor.rgb *= 0.45 + 0.6 * c2 + pow(band, 3.0) * 0.8 + bub * 0.9;
  diffuseColor.rgb *= 0.85 + 0.25 * sin(t * 2.2 + p.x * 1.3);
}`);
  };
  return mat;
}

const MAT = {};
function makeMaterials() {
  MAT.v = worldMaterial();
  MAT.tiles = worldMaterial({ noSnow: true, params: { vertexColors: false } });
  MAT.glow = new THREE.MeshBasicMaterial({ vertexColors: true });
  MAT.inst = instMaterial();
  MAT.water = waterMaterial();
}

// Pamięć podręczna kształtów bazowych - tworzone raz, potem tylko przekształcane (szybsze budowanie planszy).
const GEO = new Map();
function baseGeo(key, make) {
  let g = GEO.get(key);
  if (!g) { g = make(); if (g.index) g = g.toNonIndexed(); GEO.set(key, g); }
  return g;
}
const _bm = new THREE.Matrix4(), _bn = new THREE.Matrix3(), _bq = new THREE.Quaternion(), _be = new THREE.Euler(), _bv = new THREE.Vector3(), _bs = new THREE.Vector3(), _bp = new THREE.Vector3();

// Budowniczy: zbiera pudełka/kształty z kolorami i skleja je w jedną BufferGeometry.
// sway > 0 oznacza część, która kołysze się na wietrze (drzewa, trzciny).
class Builder {
  constructor() { this.pos = []; this.nor = []; this.col = []; this.sw = []; this.sway = 0; }
  add(geo, color, x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0, sx = 1, sy = 1, sz = 1) {
    const g = geo.index ? geo.toNonIndexed() : geo;
    _bm.compose(_bp.set(x, y, z), _bq.setFromEuler(_be.set(rx, ry, rz)), _bs.set(sx, sy, sz));
    _bn.getNormalMatrix(_bm);
    const p = g.attributes.position.array, n = g.attributes.normal.array;
    const c = color instanceof THREE.Color ? color : new THREE.Color(color);
    for (let i = 0; i < p.length; i += 3) {
      _bv.set(p[i], p[i + 1], p[i + 2]).applyMatrix4(_bm); this.pos.push(_bv.x, _bv.y, _bv.z);
      _bv.set(n[i], n[i + 1], n[i + 2]).applyMatrix3(_bn).normalize(); this.nor.push(_bv.x, _bv.y, _bv.z);
      this.col.push(c.r, c.g, c.b); this.sw.push(this.sway);
    }
    return this;
  }
  box(w, h, d, color, x = 0, y = 0, z = 0, ry = 0, rx = 0, rz = 0) {
    return this.add(baseGeo('box', () => new THREE.BoxGeometry(1, 1, 1)), color, x, y + h / 2, z, rx, ry, rz, w, h, d);
  }
  cyl(rt, rb, h, color, x = 0, y = 0, z = 0, seg = 6, rx = 0, rz = 0) {
    const k = Math.round(rt / rb * 100) / 100;
    return this.add(baseGeo('cyl' + seg + '_' + k, () => new THREE.CylinderGeometry(k, 1, 1, seg)), color, x, y + h / 2, z, rx, 0, rz, rb, h, rb);
  }
  cone(r, h, color, x = 0, y = 0, z = 0, seg = 6) {
    return this.add(baseGeo('cone' + seg, () => new THREE.ConeGeometry(1, 1, seg)), color, x, y + h / 2, z, 0, 0, 0, r, h, r);
  }
  ball(r, color, x = 0, y = 0, z = 0, det = 0, sx = 1, sy = 1, sz = 1) {
    return this.add(baseGeo('ico' + det, () => new THREE.IcosahedronGeometry(1, det)), color, x, y, z, 0, 0, 0, r * sx, r * sy, r * sz);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.nor, 3));
    g.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    if (this.sw.some(v => v > 0)) g.setAttribute('aSway', new THREE.Float32BufferAttribute(this.sw, 1));
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

function patchChunks() {
  const k = 'RE_Direct( directLight, geometryPosition';
  THREE.ShaderChunk.lights_fragment_begin = THREE.ShaderChunk.lights_fragment_begin.split(k).join('if ( directLight.visible ) ' + k);
}

function initGfx() {
  patchChunks();
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
