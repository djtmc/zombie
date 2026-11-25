// Zaplecze pod planszą (obóz, ogrodzenie, fundamenty budynków), obramowanie placu i klatka bossa.

function stripFree(x, z, pad = 0.25) {
  for (const s of SLOTS) if (Math.abs(x - s.x) < s.size / 2 + pad && Math.abs(z - s.z) < s.size / 2 + pad) return false;
  return true;
}

function decorateStrip(biome, b, g, cx, cz, x, z) {
  const wood = biome.key === 'winter' ? 0x6a5444 : 0x5a3e28;
  // płot oddzielający zaplecze od pola walki, z przejściami przed koszarami i fabryką
  if (cz === MD) {
    const fz = z - 0.42;
    const gap = SLOTS.some(s => s.kind !== 'res' && Math.abs(x - s.door.x) < 0.7);
    if (!gap && cx < MW - 1) {
      for (const ox of [-0.25, 0.25]) b.box(0.07, 0.42, 0.07, shade(wood, rr(0.85, 1.1)), x + ox, 0, fz);
      b.box(1.0, 0.05, 0.04, wood, x, 0.3, fz);
      b.box(1.0, 0.05, 0.04, wood, x, 0.14, fz);
    }
  }
  if (!stripFree(x, z)) return;
  const v = rnd();
  if (cx < 14) {
    // obóz ocalałych: namioty, skrzynie, beczki, worki z piaskiem, ognisko
    const tent = biome.key === 'winter' ? 0x8a9478 : biome.key === 'swamp' ? 0x6a6a42 : 0x6a6a4a;
    if (v < 0.2 && cz > MD) {
      const nb = new Builder();
      nb.box(0.86, 0.05, 0.42, shade(tent, 1.05), 0, 0.2, -0.13, 0, 0.75, 0);
      nb.box(0.86, 0.05, 0.42, shade(tent, 0.85), 0, 0.2, 0.13, 0, -0.75, 0);
      nb.box(0.04, 0.42, 0.04, wood, -0.42, 0, 0); nb.box(0.04, 0.42, 0.04, wood, 0.42, 0, 0);
      nb.box(0.02, 0.28, 0.2, 0x1a1612, 0.43, 0, 0);
      merge(nb, b, x + rr(-0.1, 0.1), z + rr(-0.1, 0.1));
    } else if (v < 0.34) {
      for (let i = 0; i < ri(1, 3); i++) b.box(0.24, 0.22, 0.24, shade(0x7a5a34, rr(0.8, 1.1)), x + rr(-0.3, 0.3), i > 1 ? 0.22 : 0, z + rr(-0.3, 0.3), rr(0, 1));
    } else if (v < 0.44) {
      for (let i = 0; i < ri(2, 3); i++) b.cyl(0.11, 0.11, 0.3, pick([0x4a5a3a, 0x6a3a2a, 0x3a4a5a]), x + rr(-0.3, 0.3), 0, z + rr(-0.3, 0.3), 8);
    } else if (v < 0.54) {
      for (let i = 0; i < 4; i++) b.box(0.26, 0.12, 0.15, shade(0x8a7a55, rr(0.85, 1.05)), x - 0.36 + i * 0.24, 0, z + 0.3);
      for (let i = 0; i < 3; i++) b.box(0.26, 0.12, 0.15, shade(0x8a7a55, rr(0.85, 1.05)), x - 0.24 + i * 0.24, 0.12, z + 0.3);
    } else if (v < 0.58 && cz > MD) {
      for (let i = 0; i < 6; i++) { const a = i / 6 * TAU; b.box(0.1, 0.06, 0.1, 0x5a5550, x + Math.cos(a) * 0.17, 0, z + Math.sin(a) * 0.17, a); }
      b.box(0.3, 0.05, 0.06, 0x3a2a1a, x, 0.04, z, 0.5); b.box(0.3, 0.05, 0.06, 0x3a2a1a, x, 0.04, z, -0.6);
      g.cone(0.11, 0.26, 0xff9a40, x, 0.05, z, 5);
    } else if (v < 0.66 && biome.key !== 'city') {
      b.cyl(0.05, 0.07, 0.4, 0x3a2a1a, x, 0, z, 5);
      b.cone(0.32, 0.9, biome.key === 'winter' ? 0x4a6a5a : 0x3a4a2a, x, 0.3, z, 6);
    }
  } else if (v < 0.25) {
    // przy budynkach tylko drobiazgi: skrzynki, worki, kamienie
    if (chance(0.5)) b.box(0.22, 0.2, 0.22, shade(0x7a5a34, rr(0.8, 1.1)), x + rr(-0.35, 0.35), 0, z + rr(-0.35, 0.35), rr(0, 1));
    else b.box(rr(0.1, 0.2), rr(0.05, 0.1), rr(0.1, 0.2), 0x6a665e, x + rr(-0.35, 0.35), 0, z + rr(-0.35, 0.35), rr(0, 3));
  }
}

// Obramowanie placu: krawężnik i słupki w narożnikach.
function buildPlacFrame(biome) {
  const p = MAP.plac, b = new Builder(), g = new Builder();
  const c = shade(biome.pad, 0.62), w = p.x1 - p.x0, d = p.z1 - p.z0;
  const cxm = (p.x0 + p.x1) / 2, czm = (p.z0 + p.z1) / 2;
  const curb = (x0, z0, x1, z1) => {
    // krawężnik z przerwami tam, gdzie przechodzi droga
    const n = Math.round(Math.hypot(x1 - x0, z1 - z0) / 0.5);
    for (let i = 0; i < n; i++) {
      const t = (i + 0.5) / n, x = lerp(x0, x1, t), z = lerp(z0, z1, t);
      const cx = Math.round(x + MW / 2 - 0.5), cz = Math.round(z + MD / 2 - 0.5);
      if (MAP.road.has(cellKey(clamp(cx, 0, MW - 1), clamp(cz, 0, MD - 1)))) continue;
      b.box(x1 !== x0 ? 0.46 : 0.08, 0.07, x1 !== x0 ? 0.08 : 0.46, c, x, 0, z);
    }
  };
  curb(p.x0, p.z0, p.x1, p.z0); curb(p.x0, p.z1, p.x1, p.z1);
  curb(p.x0, p.z0, p.x0, p.z1); curb(p.x1, p.z0, p.x1, p.z1);
  for (const [x, z] of [[p.x0, p.z0], [p.x1, p.z0], [p.x0, p.z1], [p.x1, p.z1]]) {
    b.box(0.14, 0.5, 0.14, shade(biome.pad, 0.5), x, 0, z);
    g.ball(0.06, 0xffc070, x, 0.56, z, 0);
  }
  const grp = new THREE.Group();
  grp.add(b.mesh());
  grp.add(g.mesh(MAT.glow, false));
  grp.userData = { w, d, cxm, czm };
  return grp;
}

// Fundament pod budynek: płyta, palisada z linek i paliki narożne.
function buildSlotBase(biome, s) {
  const b = new Builder(), h = s.size / 2;
  const c = s.kind === 'res' ? mixCol(biome.pad, 0x8a7050, 0.4) : mixCol(biome.pad, 0x707070, 0.3);
  b.box(s.size, 0.06, s.size, shade(c, 0.9), 0, 0, 0);
  b.box(s.size - 0.12, 0.02, s.size - 0.12, shade(c, 1.15), 0, 0.06, 0);
  for (const [x, z] of [[-h, -h], [h, -h], [-h, h], [h, h]]) b.box(0.05, 0.24, 0.05, 0x9a7a4a, x, 0, z);
  for (const sgn of [-1, 1]) { b.box(s.size, 0.015, 0.015, 0xd8c890, 0, 0.18, sgn * h); b.box(0.015, 0.015, s.size, 0xd8c890, sgn * h, 0.18, 0); }
  if (s.kind !== 'res') {
    // ścieżka z bramy w płocie do budynku
    b.box(0.5, 0.025, 0.7, shade(c, 0.75), 0, 0.0, -h - 0.25);
  }
  const m = b.mesh();
  const grp = new THREE.Group();
  grp.add(m);
  grp.position.set(s.x, 0, s.z);
  return grp;
}

// Klatka bossa: kamienna podstawa, cztery ściany krat (osobne siatki, by mogły odlecieć), pochodnie.
function buildCage(biome) {
  const c = MAP.cage, grp = new THREE.Group();
  const b = new Builder(), g = new Builder();
  const stone = biome.key === 'winter' ? 0x7a808a : 0x6a6560, iron = 0x7a5a44, W = 0.95, H = 2.0;
  b.box(W * 2 + 0.3, 0.16, W * 2 + 0.3, shade(stone, 0.9), 0, 0, 0);
  // ostrzegawcze pasy na krawędzi podstawy
  for (let i = 0; i < 16; i++) { const t = -W - 0.1 + (i + 0.5) * (2 * W + 0.2) / 16, c = i % 2 ? 0x1a1a1a : 0xe8b020; b.box(0.13, 0.02, 0.06, c, t, 0.16, W + 0.11); b.box(0.13, 0.02, 0.06, c, t, 0.16, -W - 0.11); b.box(0.06, 0.02, 0.13, c, W + 0.11, 0.16, t); b.box(0.06, 0.02, 0.13, c, -W - 0.11, 0.16, t); }
  // ostrzegawcze lampki na rogach podstawy
  for (const [x, z] of [[-W, -W], [W, -W], [-W, W], [W, W]]) g.ball(0.05, 0xff3020, x * 1.12, 0.22, z * 1.12, 0);
  // pochodnie i łańcuchy
  for (const sx of [-1, 1]) {
    b.box(0.05, 0.6, 0.05, 0x3a2a1a, sx * (W + 0.3), 0, W + 0.25);
    g.cone(0.08, 0.2, 0xff8a30, sx * (W + 0.3), 0.6, W + 0.25, 5);
  }
  for (let i = 0; i < 6; i++) b.box(0.04, 0.06, 0.08, 0x4a4844, -0.3 + i * 0.12, 0.16, 0.5 + (i % 2) * 0.04, i * 0.6);
  b.box(0.18, 0.12, 0.14, 0xd8d0b8, 0.5, 0.16, -0.4, 0.4); b.ball(0.08, 0xd8d0b8, 0.5, 0.33, -0.4, 0);
  grp.add(b.mesh(), g.mesh(MAT.glow, false));
  // ściany krat
  c.sides = [];
  for (let k = 0; k < 4; k++) {
    const sb = new Builder();
    const n = 9;
    for (let i = 0; i < n; i++) sb.box(0.045, H, 0.045, iron, -W + (i + 0.5) * (2 * W / n), 0, 0);
    sb.box(2 * W, 0.07, 0.07, iron, 0, H * 0.45, 0);
    sb.box(2 * W, 0.08, 0.08, iron, 0, H - 0.08, 0);
    sb.box(0.14, H + 0.1, 0.14, shade(iron, 0.8), W, 0, 0); // słupek narożny (każda ściana ma jeden)
    const m = sb.mesh();
    const piv = new THREE.Group();
    const a = k * Math.PI / 2;
    piv.position.set(Math.sin(a) * W, 0.16, Math.cos(a) * W);
    piv.rotation.y = a; // lokalna oś x biegnie wzdłuż krawędzi, z na zewnątrz klatki
    piv.add(m);
    piv.userData = { a, v: null };
    grp.add(piv);
    c.sides.push(piv);
  }
  const roof = new Builder();
  for (let i = 0; i < 6; i++) { roof.box(2 * W, 0.05, 0.05, iron, 0, 0, -W + (i + 0.5) * (2 * W / 6)); roof.box(0.05, 0.05, 2 * W, iron, -W + (i + 0.5) * (2 * W / 6), 0, 0); }
  const rm = roof.mesh();
  const rp = new THREE.Group(); rp.position.y = 0.16 + H; rp.add(rm); rp.userData = { a: 0, v: null, roof: true };
  grp.add(rp); c.sides.push(rp);
  c.light = [0xff5a3a, 3.5, 4, c.x, 2.4, c.z];
  grp.position.set(c.x, 0, c.z);
  c.grp = grp;
  return grp;
}
