// Modele postaci z pudełek: zombie (człekokształtne, psy, bossowie) i żołnierze.
// Części (nogi, tułów z głową, ręce) są osobnymi siatkami, żeby dało się je animować.
const RIG_CACHE = new Map();

function humanParts(L) {
  const s = L.size || 1, w = L.w || 1;
  const skin = col(L.skin), shirt = col(L.shirt), pants = col(L.pants);
  const P = {};
  // noga: obrót w biodrze (y = 0)
  const leg = new Builder();
  leg.box(0.13 * w, 0.42, 0.14, pants, 0, -0.42, 0);
  leg.box(0.14 * w, 0.06, 0.2, L.shoe || 0x2a2420, 0, -0.45, 0.03);
  if (L.legExtra) L.legExtra(leg);
  P.leg = leg.geometry();
  // tułów z głową: dół w biodrze
  const t = new Builder();
  t.box(0.36 * w, 0.4, 0.21, shirt, 0, 0, 0);
  t.box(0.3 * w, 0.06, 0.2, shade(L.shirt, 0.75), 0, 0.02, 0.01);
  t.box(0.09, 0.06, 0.09, skin, 0, 0.4, 0.01);
  t.box(0.23, 0.23, 0.22, skin, 0, 0.45, 0.02);
  t.box(0.05, 0.035, 0.02, L.eye || 0xd8e05a, -0.055, 0.56, 0.135);
  t.box(0.05, 0.035, 0.02, L.eye || 0xd8e05a, 0.055, 0.56, 0.135);
  t.box(0.1, 0.03, 0.02, 0x2a0a08, 0, 0.49, 0.135);
  if (L.hair) t.box(0.24, 0.06, 0.23, L.hair, 0, 0.67, 0.02);
  if (L.torsoExtra) L.torsoExtra(t, skin, shirt);
  P.torso = t.geometry();
  // ręka: obrót w barku
  const a = new Builder();
  a.box(0.1, 0.24, 0.11, shirt, 0, -0.24, 0);
  a.box(0.09, 0.18, 0.1, skin, 0, -0.42, 0);
  if (L.armExtra) L.armExtra(a, skin);
  P.arm = a.geometry();
  if (L.armRExtra) { const ar = new Builder(); ar.box(0.1, 0.24, 0.11, shirt, 0, -0.24, 0); ar.box(0.09, 0.18, 0.1, skin, 0, -0.42, 0); L.armRExtra(ar, skin); P.armR = ar.geometry(); }
  if (L.glowExtra) { const g = new Builder(); L.glowExtra(g); P.glow = g.geometry(); }
  P.s = s;
  return P;
}

function dogParts(L) {
  const c = col(L.skin), d = shade(L.skin, 0.7);
  const P = {};
  const body = new Builder();
  body.box(0.22, 0.2, 0.5, c, 0, -0.05, 0);
  body.box(0.08, 0.03, 0.4, 0x5a0d0a, 0.08, 0.15, -0.02);
  body.box(0.16, 0.16, 0.2, c, 0, 0.05, 0.3);
  body.box(0.1, 0.08, 0.14, d, 0, 0.04, 0.44);
  body.box(0.06, 0.03, 0.02, 0xff5a3a, -0.04, 0.16, 0.4);
  body.box(0.06, 0.03, 0.02, 0xff5a3a, 0.04, 0.16, 0.4);
  body.box(0.04, 0.08, 0.04, d, -0.06, 0.21, 0.28); body.box(0.04, 0.08, 0.04, d, 0.06, 0.21, 0.28);
  body.box(0.04, 0.04, 0.22, d, 0, 0.08, -0.32, 0, 0.5);
  P.torso = body.geometry();
  const leg = new Builder();
  leg.box(0.06, 0.22, 0.07, d, 0, -0.22, 0);
  P.leg = leg.geometry();
  P.dog = true; P.s = L.size || 1;
  return P;
}

function getRig(key, look, tint) {
  const ck = key + '|' + (tint || 0);
  if (RIG_CACHE.has(ck)) return RIG_CACHE.get(ck);
  const L = Object.assign({}, look);
  if (tint) L.skin = mixCol(L.skin, tint, 0.35).getHex();
  const P = look.dog ? dogParts(L) : humanParts(L);
  RIG_CACHE.set(ck, P);
  return P;
}

// Tworzy instancję postaci. Zwraca obiekt z grupą i częściami do animacji.
function makeBody(P, mat = MAT.v) {
  const root = new THREE.Group();
  const hip = new THREE.Group();
  root.add(hip);
  const m = (g, mt = mat) => { const x = new THREE.Mesh(g, mt); x.castShadow = true; return x; };
  const B = { root, hip, dog: !!P.dog, s: P.s };
  if (P.dog) {
    hip.position.y = 0.27;
    B.torso = m(P.torso); hip.add(B.torso);
    B.legs = [];
    for (const [x, z] of [[-0.08, 0.18], [0.08, 0.18], [-0.08, -0.18], [0.08, -0.18]]) {
      const g = new THREE.Group(); g.position.set(x, -0.08, z); g.add(m(P.leg)); hip.add(g); B.legs.push(g);
    }
  } else {
    hip.position.y = 0.48;
    B.torso = new THREE.Group(); hip.add(B.torso);
    B.torso.add(m(P.torso));
    if (P.glow) B.torso.add(new THREE.Mesh(P.glow, MAT.glow));
    B.armL = new THREE.Group(); B.armL.position.set(-0.24, 0.36, 0); B.armL.add(m(P.arm));
    B.armR = new THREE.Group(); B.armR.position.set(0.24, 0.36, 0); B.armR.add(m(P.armR || P.arm));
    B.torso.add(B.armL, B.armR);
    B.legL = new THREE.Group(); B.legL.position.set(-0.09, 0, 0); B.legL.add(m(P.leg));
    B.legR = new THREE.Group(); B.legR.position.set(0.09, 0, 0); B.legR.add(m(P.leg));
    hip.add(B.legL, B.legR);
  }
  root.scale.setScalar(P.s * 0.62);
  return B;
}

// gait: 'shamble' | 'run' | 'crawl' | 'soldier' | 'dog'; phase w radianach.
function animBody(B, gait, phase, moving, hunch = 0.25) {
  const sw = moving ? 1 : 0.15;
  if (B.dog) {
    const k = Math.sin(phase) * 0.7 * sw;
    B.legs[0].rotation.x = k; B.legs[3].rotation.x = k; B.legs[1].rotation.x = -k; B.legs[2].rotation.x = -k;
    B.hip.position.y = 0.27 + Math.abs(Math.sin(phase)) * 0.04 * sw;
    return;
  }
  const k = Math.sin(phase);
  if (gait === 'crawl') {
    B.hip.position.y = 0.16;
    B.torso.rotation.x = 1.35;
    B.legL.rotation.x = 1.2 + k * 0.3 * sw; B.legR.rotation.x = 1.2 - k * 0.3 * sw;
    B.armL.rotation.x = -2.6 + k * 0.6 * sw; B.armR.rotation.x = -2.6 - k * 0.6 * sw;
    return;
  }
  const amp = gait === 'run' ? 0.9 : gait === 'soldier' ? 0.6 : 0.45;
  B.legL.rotation.x = k * amp * sw; B.legR.rotation.x = -k * amp * sw;
  B.hip.position.y = 0.48 + Math.abs(Math.cos(phase)) * (gait === 'run' ? 0.05 : 0.025) * sw;
  if (gait === 'soldier') {
    B.torso.rotation.x = 0.05; B.torso.rotation.z = 0;
    B.armL.rotation.x = -1.35; B.armR.rotation.x = -1.2 + k * 0.05;
    B.armL.rotation.z = -0.35; B.armR.rotation.z = 0.15;
  } else {
    B.torso.rotation.x = hunch + (gait === 'run' ? 0.25 : 0);
    B.torso.rotation.z = Math.sin(phase * 0.5) * 0.12 * sw;
    B.armL.rotation.x = -1.45 + Math.sin(phase + 1) * 0.18; B.armR.rotation.x = -1.25 + Math.sin(phase) * 0.2;
    B.armL.rotation.z = 0.08; B.armR.rotation.z = -0.08;
  }
}

// Żołnierz posterunku
const SOLDIER_LOOK = {
  skin: 0xd8a882, shirt: 0x4a5a32, pants: 0x3c4428, shoe: 0x1c1a16, eye: 0x1a1a1a,
  torsoExtra: (t) => { t.box(0.27, 0.1, 0.26, 0x3d4a2a, 0, 0.62, 0.02); t.box(0.38, 0.14, 0.23, 0x33402a, 0, 0.16, 0); },
  armRExtra: (a) => { a.box(0.05, 0.05, 0.5, 0x1e1e1e, 0, -0.44, 0.18); }
};
