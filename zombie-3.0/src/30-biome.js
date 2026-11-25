// Biomy: każda plansza (5 fal + boss) toczy się w innej krainie.
const BIOMES = [
  {
    key: 'city', name: 'Zrujnowane Miasto', sub: 'Płonące ulice, rozbite auta i popiół w powietrzu',
    fog: 0x1a1214, fogNear: 34, fogFar: 80,
    hemiSky: 0x9a94b0, hemiGround: 0x3a2c22, hemiI: 1.0,
    sun: 0xffc08a, sunI: 2.0, sunPos: [-14, 22, 10],
    ground: [0x6a645c, 0x5c5750, 0x726a5e], road: 0x2c2c33, roadLine: 0xd8b84a, pad: 0x6b6258, cliff: 0x2b2522,
    tint: [1.03, 0.99, 0.95], lift: [0.014, 0.01, 0.014], exposure: 1.15,
    weather: 'ash', zombieTint: 0x7a8a62, boss: 'butcher', decorLight: 0xff7a2a
  },
  {
    key: 'winter', name: 'Zimowa Autostrada', sub: 'Zaspy, zamarznięte ciężarówki i śnieżyca',
    fog: 0x9aa8bd, fogNear: 30, fogFar: 85,
    hemiSky: 0xc9d8f0, hemiGround: 0x6a7080, hemiI: 1.0,
    sun: 0xe8f0ff, sunI: 1.7, sunPos: [12, 24, 12],
    ground: [0xd8e0ea, 0xc5d0de, 0xe6ecf3], road: 0x4a505c, roadLine: 0xc9d3e0, pad: 0x8c97a6, cliff: 0x6c7584,
    tint: [0.93, 0.98, 1.08], lift: [0.012, 0.016, 0.03], exposure: 0.95,
    weather: 'snow', zombieTint: 0x8fa3b0, boss: 'giant', decorLight: 0xff9a40
  },
  {
    key: 'swamp', name: 'Toksyczne Bagno', sub: 'Zatruta woda przy starej fabryce chemicznej',
    fog: 0x16201a, fogNear: 26, fogFar: 70,
    hemiSky: 0x9ab09a, hemiGround: 0x2c3426, hemiI: 1.0,
    sun: 0xd8f0b0, sunI: 1.7, sunPos: [-10, 20, -8],
    ground: [0x46522f, 0x3c4830, 0x52603a], road: 0x7a6a4a, roadLine: 0x6b6040, pad: 0x8a8a72, cliff: 0x262b1c,
    tint: [0.94, 1.06, 0.92], lift: [0.008, 0.02, 0.01], exposure: 1.1,
    weather: 'spores', zombieTint: 0x6f9a52, boss: 'queen', decorLight: 0x7dff5a
  }
];

// ---- rekwizyty: proste modele z pudełek, osobne dla każdego biomu ----
function propRubble(b, base) {
  for (let i = 0; i < ri(2, 4); i++) b.box(rr(0.12, 0.35), rr(0.06, 0.18), rr(0.12, 0.35), shade(base, rr(0.7, 1.1)), rr(-0.35, 0.35), 0, rr(-0.35, 0.35), rr(0, 3));
}
function propRuin(b) {
  const c = pick([0x6a5d52, 0x5b5550, 0x77665a]);
  const h = rr(0.9, 2.2), w = rr(0.6, 0.85);
  b.box(w, h, 0.18, shade(c, 1), 0, 0, -0.3, 0);
  b.box(0.18, h * rr(0.5, 0.9), w * 0.8, shade(c, 0.85), -w / 2 + 0.09, 0, 0.05, 0);
  for (let i = 0; i < 3; i++) b.box(0.16, 0.14, 0.02, 0x1a1512, rr(-0.2, 0.2), rr(0.3, h - 0.3), -0.2);
  b.box(w * 0.9, 0.08, 0.5, shade(c, 0.7), 0.05, h * 0.55, -0.1, 0, 0.35, 0.1);
  propRubble(b, c);
}
function propCar(b, rust) {
  const c = rust ? pick([0x7a3d28, 0x5d4a3a, 0x4d5560, 0x7a6a3a]) : pick([0xb03a2e, 0x2e5a8a, 0xd8d0c0, 0x3a6a3a]);
  const ry = rr(-0.5, 0.5) + (chance(0.5) ? Math.PI / 2 : 0);
  const cx = Math.cos(ry), sx = Math.sin(ry);
  const P = (x, z) => [x * cx + z * sx, -x * sx + z * cx];
  let p = P(0, 0); b.box(0.85, 0.22, 0.42, c, p[0], 0.1, p[1], ry);
  p = P(-0.05, 0); b.box(0.48, 0.17, 0.38, shade(c, 0.85), p[0], 0.32, p[1], ry);
  b.box(0.46, 0.12, 0.36, 0x22262c, p[0], 0.34, p[1], ry);
  for (const [x, z] of [[0.27, 0.2], [-0.27, 0.2], [0.27, -0.2], [-0.27, -0.2]]) { p = P(x, z); b.cyl(0.09, 0.09, 0.08, 0x151515, p[0], 0.02, p[1], 6, Math.PI / 2); }
}
function propBarrel(b, color) { b.cyl(0.13, 0.13, 0.34, color, rr(-0.2, 0.2), 0, rr(-0.2, 0.2), 7); }
function propLamp(b) { b.cyl(0.03, 0.04, 1.5, 0x2a2a2e, 0, 0, 0); b.box(0.35, 0.05, 0.06, 0x2a2a2e, 0.15, 1.45, 0); }
function propPine(b, snow) {
  const h = rr(0.9, 1.6);
  b.cyl(0.06, 0.08, 0.3, 0x4a3426, 0, 0, 0);
  for (let i = 0; i < 3; i++) {
    const r = (0.5 - i * 0.13) * h / 1.2, y = 0.25 + i * h * 0.27;
    b.cone(r, h * 0.42, 0x23402e, 0, y, 0, 7);
    if (snow) b.cone(r * 0.7, h * 0.2, 0xeef3f8, 0, y + h * 0.24, 0, 7);
  }
}
function propDeadTree(b, c) {
  b.cyl(0.05, 0.09, 1.1, c, 0, 0, 0, 5);
  for (let i = 0; i < 3; i++) b.cyl(0.02, 0.04, rr(0.35, 0.6), c, 0, rr(0.5, 0.95), 0, 4, rr(-1, 1), rr(-1.1, 1.1));
}
function propTruck(b) {
  const ry = chance(0.5) ? 0 : Math.PI / 2;
  const c = pick([0x7d8a96, 0x9a7a4a, 0x5a6a7a]);
  b.box(1.4, 0.55, 0.55, c, 0, 0.12, 0, ry);
  b.box(1.2, 0.08, 0.5, 0xf2f6fa, 0, 0.67, 0, ry);
  const off = 0.85, cx = Math.cos(ry), sx = Math.sin(ry);
  b.box(0.45, 0.45, 0.55, shade(c, 0.8), off * cx, 0.12, -off * sx, ry);
  b.box(0.42, 0.08, 0.5, 0xf2f6fa, off * cx, 0.57, -off * sx, ry);
}
function propSnowbank(b) { for (let i = 0; i < 3; i++) b.ball(rr(0.18, 0.32), 0xeef3f8, rr(-0.3, 0.3), 0.05, rr(-0.3, 0.3), 1, 1.4, 0.5, 1.2); }
function propReeds(b) { for (let i = 0; i < 6; i++) b.cyl(0.012, 0.02, rr(0.3, 0.6), pick([0x5a6a32, 0x6b7a3a, 0x4a5528]), rr(-0.35, 0.35), 0, rr(-0.35, 0.35), 4, rr(-0.2, 0.2), rr(-0.2, 0.2)); }
function propTank(b) {
  b.cyl(0.38, 0.38, 0.9, 0x6b6e60, 0, 0, 0, 10);
  b.cyl(0.4, 0.4, 0.06, 0x4a4c40, 0, 0.9, 0, 10);
  b.box(0.06, 1.1, 0.06, 0x3a3a30, 0.38, 0, 0);
  b.box(0.8, 0.12, 0.2, 0x8a7a2a, 0, 0.45, 0.33);
}
function propSign(b) {
  b.cyl(0.03, 0.03, 0.8, 0x3a3a3a, 0, 0, 0);
  b.box(0.5, 0.3, 0.03, 0xd4b12a, 0, 0.75, 0);
  b.box(0.12, 0.14, 0.035, 0x1a1a1a, 0, 0.83, 0);
}

// Wypełnia jedno wolne pole planszy rekwizytami danego biomu. Zwraca [builder, glow builder, światło?].
function decorateCell(biome, b, g, x, z, nearRoad) {
  const out = { light: null };
  const k = biome.key;
  const at = (fn) => { const nb = new Builder(); fn(nb); merge(nb, b, x, z); };
  const atG = (fn) => { const nb = new Builder(); fn(nb); merge(nb, g, x, z); };
  const v = rnd();
  if (k === 'city') {
    if (v < 0.22 && !nearRoad) at(propRuin);
    else if (v < 0.36) at(nb => propCar(nb, true));
    else if (v < 0.46) { at(nb => propBarrel(nb, 0x6a4a2a)); if (chance(0.5)) { atG(nb => nb.ball(0.12, 0xff8a30, 0, 0.4, 0, 0)); out.light = [0xff7a2a, 3.2, 3.5, x, 0.7, z]; } }
    else if (v < 0.52 && nearRoad) at(propLamp);
    else if (v < 0.75) at(nb => propRubble(nb, 0x6a6058));
  } else if (k === 'winter') {
    if (v < 0.28) at(nb => propPine(nb, true));
    else if (v < 0.36) at(propTruck);
    else if (v < 0.44) at(nb => propCar(nb, false));
    else if (v < 0.62) at(propSnowbank);
    else if (v < 0.66) { if (nearRoad) at(propSign); }
    else if (v < 0.675) { at(nb => { nb.box(0.5, 0.06, 0.5, 0x4a3a2a, 0, 0, 0); }); atG(nb => nb.cone(0.15, 0.3, 0xff9a40, 0, 0.05, 0, 5)); out.light = [0xff9a40, 3.0, 3.2, x, 0.6, z]; }
  } else {
    if (v < 0.22) at(nb => propDeadTree(nb, 0x3a3226));
    else if (v < 0.4) at(propReeds);
    else if (v < 0.48 && !nearRoad) at(propTank);
    else if (v < 0.58) at(nb => { propBarrel(nb, 0x8a7a1a); propBarrel(nb, 0x5a6a2a); });
    else if (v < 0.66) { atG(nb => { for (let i = 0; i < 4; i++) nb.box(rr(0.3, 0.55), 0.02, rr(0.3, 0.55), pick([0x2f9a22, 0x3aa82a, 0x27801c]), rr(-0.18, 0.18), 0.01, rr(-0.18, 0.18), rr(0, 1.5)); }); if (chance(0.35)) out.light = [0x6dff4a, 2.2, 3, x, 0.4, z]; out.pool = true; }
  }
  return out;
}
// Przenosi gotowy model w miejsce pola (x, z) i dokleja do zbiorczego budowniczego.
function merge(src, dst, x, z) {
  for (let i = 0; i < src.pos.length; i += 3) { dst.pos.push(src.pos[i] + x, src.pos[i + 1], src.pos[i + 2] + z); }
  for (const n of src.nor) dst.nor.push(n);
  for (const c of src.col) dst.col.push(c);
}
