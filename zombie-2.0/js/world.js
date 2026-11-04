// =====================================================================
//  ŚWIAT: teren, roślinność, forteca gracza, krypta zombie, klatka bossa
// =====================================================================
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { MAP, ARMATA_SLOTS } from './config.js';
import { mulberry32, fbm, smoothstep, paint, place, noiseTexture } from './utils.js';

const STONE = 0x8a8478, STONE_DARK = 0x5d5850, WOOD = 0x6b4a2f, ROOF = 0x7a2020;

export class World {
  constructor(scene, quality) {
    this.scene = scene;
    this.group = new THREE.Group();
    scene.add(this.group);
    this.time = 0;
    this.rnd = mulberry32(1337);
    this.decor = new THREE.Group();
    this.group.add(this.decor);

    this._terrain();
    this._fortress();
    this._crypt();
    this._slots();
    this._fence();
    this._placementOverlay();
    this.buildDecor(quality);
  }

  // ------------------------------------------------------------- TEREN
  heightAt(x, z) {
    const ex = Math.max(0, Math.abs(x) - (MAP.halfW + 4));
    const ez = Math.max(0, Math.abs(z) - (MAP.halfD + 3));
    const edge = smoothstep(0, 22, Math.hypot(ex, ez));
    return edge * (fbm(x * 0.03 + 10, z * 0.03, 4) * 16 - 2) + edge * edge * 6;
  }

  _terrain() {
    const W = MAP.width + 150, D = MAP.depth + 140;
    const geo = new THREE.PlaneGeometry(W, D, 200, 130);
    geo.rotateX(-Math.PI / 2);
    const pos = geo.attributes.position;
    const colors = new Float32Array(pos.count * 3);
    const grassA = new THREE.Color(0x4c6c30), grassB = new THREE.Color(0x6e8240), dry = new THREE.Color(0x8a7a46);
    const dirt = new THREE.Color(0x6e5638), cursed = new THREE.Color(0x3a2a35), cobble = new THREE.Color(0x77705f);
    const rock = new THREE.Color(0x5f5a52);
    const c = new THREE.Color();
    for (let i = 0; i < pos.count; i++) {
      const x = pos.getX(i), z = pos.getZ(i);
      const h = this.heightAt(x, z);
      pos.setY(i, h);
      const n = fbm(x * 0.08, z * 0.08, 3);
      c.copy(grassA).lerp(grassB, n);
      c.lerp(dry, smoothstep(0.55, 0.8, fbm(x * 0.025 + 40, z * 0.025, 3)) * 0.7);
      // wydeptana ścieżka od krypty do fortecy
      const road = smoothstep(7, 2.5, Math.abs(z + Math.sin(x * 0.07) * 3.5));
      const inField = smoothstep(MAP.halfW + 6, MAP.halfW - 2, Math.abs(x));
      c.lerp(dirt, road * inField * (0.55 + n * 0.3));
      // przeklęta ziemia przy krypcie
      const dSpawn = Math.hypot(x - MAP.spawnX, z);
      c.lerp(cursed, smoothstep(18, 6, dSpawn) * 0.85);
      // bruk przy fortecy
      const dBase = Math.hypot(x - MAP.baseX, z);
      c.lerp(cobble, smoothstep(10, 6, dBase) * 0.8);
      // skały na zboczach
      c.lerp(rock, smoothstep(3, 9, h) * 0.6);
      colors[i * 3] = c.r; colors[i * 3 + 1] = c.g; colors[i * 3 + 2] = c.b;
    }
    geo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
    geo.computeVertexNormals();
    const tex = noiseTexture(256, 3);
    tex.repeat.set(W / 6, D / 6);
    const mat = new THREE.MeshStandardMaterial({ vertexColors: true, map: tex, roughness: 0.97, metalness: 0 });
    this.ground = new THREE.Mesh(geo, mat);
    this.ground.receiveShadow = true;
    this.group.add(this.ground);
  }

  // ------------------------------------------------------------- FORTECA
  _fortress() {
    const g = new THREE.Group();
    const parts = [];
    const box = (w, h, d, x, y, z, col, ry = 0) => parts.push(paint(place(new THREE.BoxGeometry(w, h, d), x, y, z, 0, ry), col));
    const cyl = (r1, r2, h, x, y, z, col, seg = 10) => parts.push(paint(place(new THREE.CylinderGeometry(r1, r2, h, seg), x, y, z), col));
    const cone = (r, h, x, y, z, col, seg = 8) => parts.push(paint(place(new THREE.ConeGeometry(r, h, seg), x, y, z), col));

    box(11.5, 0.6, 11.5, 0, 0.3, 0, STONE_DARK);              // platforma
    box(6.5, 6.5, 6.5, 0, 3.85, 0, STONE);                    // donżon
    for (let i = -2; i <= 2; i++) {                            // blanki
      for (const [sx, sz] of [[i * 1.3, 3.25], [i * 1.3, -3.25], [3.25, i * 1.3], [-3.25, i * 1.3]]) {
        box(0.7, 0.8, 0.7, sx, 7.5, sz, STONE);
      }
    }
    for (const [tx, tz] of [[-4.8, -4.8], [4.8, -4.8], [-4.8, 4.8], [4.8, 4.8]]) {  // wieże
      cyl(1.35, 1.55, 8.5, tx, 4.55, tz, STONE, 12);
      cyl(1.7, 1.7, 0.5, tx, 8.9, tz, STONE_DARK, 12);
      cone(1.9, 3, tx, 10.6, tz, ROOF, 12);
    }
    box(0.8, 4.2, 2.8, -3.3, 2.7, 0, 0x2a1e15);                // brama
    box(0.3, 3.6, 2.2, -3.6, 2.4, 0, WOOD);
    cone(2.6, 2.2, 0, 8.4, 0, ROOF, 4);                        // dach donżonu
    parts[parts.length - 1].rotateY(Math.PI / 4);
    const merged = mergeGeometries(parts);
    const mesh = new THREE.Mesh(merged, new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, flatShading: true }));
    mesh.castShadow = mesh.receiveShadow = true;
    g.add(mesh);

    // świecące okna (bloom)
    const winMat = new THREE.MeshStandardMaterial({ color: 0x331100, emissive: 0xffa040, emissiveIntensity: 2.2 });
    const winGeo = new THREE.BoxGeometry(0.15, 0.9, 0.6);
    for (const [x, y, z, ry] of [[-3.28, 5, -1.8, 0], [-3.28, 5, 1.8, 0], [3.28, 5, 0, 0], [0, 5, 3.28, Math.PI / 2], [0, 5, -3.28, Math.PI / 2]]) {
      const w = new THREE.Mesh(winGeo, winMat); w.position.set(x, y, z); w.rotation.y = ry; g.add(w);
    }
    for (const [tx, tz] of [[-4.8, -4.8], [-4.8, 4.8]]) {
      const w = new THREE.Mesh(winGeo, winMat); w.position.set(tx - 1.36, 6.2, tz); g.add(w);
    }

    // maszt + powiewająca flaga
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 4.5), new THREE.MeshStandardMaterial({ color: 0x333333, metalness: 0.6, roughness: 0.4 }));
    pole.position.set(0, 11.2, 0); g.add(pole);
    const flagGeo = new THREE.PlaneGeometry(2.2, 1.3, 14, 6);
    flagGeo.translate(1.1, 0, 0);
    this.flagBase = flagGeo.attributes.position.array.slice();
    this.flag = new THREE.Mesh(flagGeo, new THREE.MeshStandardMaterial({ color: 0xc0262b, side: THREE.DoubleSide, roughness: 0.7 }));
    this.flag.position.set(0, 12.6, 0);
    this.flag.castShadow = true;
    g.add(this.flag);

    // pochodnia przy bramie
    this.torch = new THREE.PointLight(0xff8a3a, 30, 22, 1.6);
    this.torch.position.set(-5, 4, 0);
    g.add(this.torch);
    this.torchSpots = [new THREE.Vector3(MAP.baseX - 4.2, 4.6, -1.9), new THREE.Vector3(MAP.baseX - 4.2, 4.6, 1.9)];
    for (const p of this.torchSpots) {
      const t = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.1, 1), new THREE.MeshStandardMaterial({ color: WOOD }));
      t.position.set(p.x - MAP.baseX, p.y - 0.6, p.z); g.add(t);
    }

    g.position.set(MAP.baseX, 0, MAP.baseZ);
    this.base = g;
    this.group.add(g);
  }

  // ------------------------------------------------------------- KRYPTA + KLATKA
  _crypt() {
    const parts = [];
    const x0 = MAP.spawnX - 5;
    const box = (w, h, d, x, y, z, col) => parts.push(paint(place(new THREE.BoxGeometry(w, h, d), x, y, z), col));
    box(3, 7, 3, x0, 3.5, -7, 0x45404a);
    box(3, 7, 3, x0, 3.5, 7, 0x45404a);
    box(3.6, 2, 17, x0, 7.8, 0, 0x3a3540);
    box(1.2, 1.2, 1.2, x0, 9.4, -7, 0x3a3540);
    box(1.2, 1.2, 1.2, x0, 9.4, 7, 0x3a3540);
    // nagrobki wokół
    const rnd = this.rnd;
    for (let i = 0; i < 22; i++) {
      const a = rnd() * Math.PI * 2, r = 9 + rnd() * 9;
      const x = MAP.spawnX + Math.cos(a) * r, z = Math.sin(a) * r * 1.4;
      if (x > MAP.spawnX + 5 && Math.abs(z) < 12) continue;
      if (Math.abs(z) > MAP.halfD - 2) continue;
      const h = 0.9 + rnd() * 0.7;
      const geo = rnd() < 0.5 ? new THREE.BoxGeometry(0.9, h, 0.25) : new THREE.CylinderGeometry(0.45, 0.45, 0.25, 10, 1, false, 0, Math.PI);
      if (geo.type === 'CylinderGeometry') { geo.rotateX(Math.PI / 2); geo.rotateZ(Math.PI / 2); geo.translate(0, h / 2, 0); }
      parts.push(paint(place(geo, x, h / 2, z, (rnd() - 0.5) * 0.3, rnd() * Math.PI, (rnd() - 0.5) * 0.3), 0x6b6670));
    }
    const mesh = new THREE.Mesh(mergeGeometries(parts.map(p => p.index ? p.toNonIndexed() : p)), new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, flatShading: true }));
    mesh.castShadow = mesh.receiveShadow = true;
    this.group.add(mesh);

    // fioletowa poświata portalu
    const portal = new THREE.Mesh(new THREE.PlaneGeometry(11, 6.5), new THREE.MeshBasicMaterial({
      color: 0x9a40ff, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false, toneMapped: false,
      blending: THREE.AdditiveBlending,
    }));
    portal.position.set(x0, 3.4, 0);
    portal.rotation.y = Math.PI / 2;
    this.portal = portal;
    this.group.add(portal);
    this.spawnLight = new THREE.PointLight(0xa050ff, 40, 30, 1.6);
    this.spawnLight.position.set(MAP.spawnX, 4, 0);
    this.group.add(this.spawnLight);

    // klatka bossa (pręty + rama)
    const bars = [];
    for (let i = -3; i <= 3; i++) for (let j = -3; j <= 3; j++) {
      if (Math.abs(i) !== 3 && Math.abs(j) !== 3) continue;
      bars.push(place(new THREE.CylinderGeometry(0.11, 0.11, 6.5, 6), i * 1.1, 3.25, j * 1.1));
    }
    bars.push(place(new THREE.BoxGeometry(7, 0.3, 7), 0, 6.5, 0));
    bars.push(place(new THREE.BoxGeometry(7, 0.3, 7), 0, 0.15, 0));
    this.cage = new THREE.Mesh(mergeGeometries(bars.map(b => b.index ? b.toNonIndexed() : b)),
      new THREE.MeshStandardMaterial({ color: 0x2a2a2e, metalness: 0.85, roughness: 0.35 }));
    this.cage.castShadow = true;
    this.cage.position.set(MAP.spawnX, 0, 0);
    this.cageState = 'closed'; // closed | opening | open
    this.group.add(this.cage);
  }

  closeCage() { this.cageState = 'closed'; this.cage.position.y = 0; this.cage.visible = true; }
  openCage() { if (this.cageState === 'closed') this.cageState = 'opening'; }

  // ------------------------------------------------------------- PLATFORMY WIELKIEJ ARMATY
  _slots() {
    this.slotRings = [];
    const plat = new THREE.MeshStandardMaterial({ color: 0x6a665e, roughness: 0.8, flatShading: true });
    const ringMat = new THREE.MeshBasicMaterial({ color: 0x40e0ff, transparent: true, opacity: 0.8, toneMapped: false });
    for (const s of ARMATA_SLOTS) {
      const p = new THREE.Mesh(new THREE.CylinderGeometry(2.1, 2.4, 0.8, 8), plat);
      p.position.set(s.x, 0.4, s.z);
      p.castShadow = p.receiveShadow = true;
      this.group.add(p);
      const ring = new THREE.Mesh(new THREE.TorusGeometry(1.7, 0.07, 6, 40), ringMat);
      ring.rotation.x = Math.PI / 2;
      ring.position.set(s.x, 0.85, s.z);
      this.group.add(ring);
      this.slotRings.push(ring);
    }
  }
  setSlotUsed(i, used) { this.slotRings[i].visible = !used; }

  // ------------------------------------------------------------- PŁOT NA BRZEGACH
  _fence() {
    const posts = [], rails = [];
    for (const side of [-1, 1]) {
      const z = side * (MAP.halfD + 1.2);
      for (let x = -MAP.halfW + 2; x <= MAP.halfW - 2; x += 3) {
        const tilt = (this.rnd() - 0.5) * 0.25;
        posts.push(place(new THREE.BoxGeometry(0.25, 1.6, 0.25), x, 0.8, z, tilt, 0, tilt));
        if (this.rnd() > 0.15) rails.push(place(new THREE.BoxGeometry(3, 0.15, 0.1), x + 1.5, 1.1 + (this.rnd() - 0.5) * 0.2, z, 0, 0, (this.rnd() - 0.5) * 0.15));
      }
    }
    const mat = new THREE.MeshStandardMaterial({ color: 0x5a4330, roughness: 0.95 });
    const m = new THREE.Mesh(mergeGeometries([...posts, ...rails]), mat);
    m.castShadow = m.receiveShadow = true;
    this.group.add(m);
  }

  // ------------------------------------------------------------- SIATKA BUDOWANIA
  _placementOverlay() {
    const geo = new THREE.PlaneGeometry(MAP.width, MAP.depth);
    geo.rotateX(-Math.PI / 2);
    this.overlayMat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false,
      uniforms: { uCursor: { value: new THREE.Vector2() }, uOk: { value: 1 } },
      vertexShader: /* glsl */`
        varying vec2 vXZ;
        void main() { vec4 w = modelMatrix * vec4(position, 1.0); vXZ = w.xz; gl_Position = projectionMatrix * viewMatrix * w; }`,
      fragmentShader: /* glsl */`
        uniform vec2 uCursor; uniform float uOk; varying vec2 vXZ;
        void main() {
          vec2 g = abs(fract(vXZ - 0.5) - 0.5) / fwidth(vXZ);
          float line = 1.0 - min(min(g.x, g.y), 1.0);
          float d = length(vXZ - uCursor);
          float fade = smoothstep(14.0, 2.0, d);
          vec3 col = mix(vec3(1.0, 0.3, 0.3), vec3(0.5, 1.0, 0.6), uOk);
          gl_FragColor = vec4(col, line * fade * 0.45 + fade * 0.04);
        }`,
    });
    this.overlay = new THREE.Mesh(geo, this.overlayMat);
    this.overlay.position.y = 0.03;
    this.overlay.visible = false;
    this.overlay.renderOrder = 2;
    this.group.add(this.overlay);

    this.rangeRing = new THREE.Mesh(new THREE.RingGeometry(0.97, 1, 96), new THREE.MeshBasicMaterial({
      color: 0x80ffff, transparent: true, opacity: 0.5, depthWrite: false, toneMapped: false }));
    this.rangeRing.rotation.x = -Math.PI / 2;
    this.rangeRing.position.y = 0.05;
    this.rangeRing.visible = false;
    this.group.add(this.rangeRing);
    this.rangeDisc = new THREE.Mesh(new THREE.CircleGeometry(1, 64), new THREE.MeshBasicMaterial({
      color: 0x80ffff, transparent: true, opacity: 0.07, depthWrite: false }));
    this.rangeDisc.rotation.x = -Math.PI / 2;
    this.rangeDisc.position.y = 0.04;
    this.rangeDisc.visible = false;
    this.group.add(this.rangeDisc);
  }

  showRange(x, z, r, ok = true) {
    const vis = r > 0;
    this.rangeRing.visible = this.rangeDisc.visible = vis;
    if (!vis) return;
    this.rangeRing.position.x = this.rangeDisc.position.x = x;
    this.rangeRing.position.z = this.rangeDisc.position.z = z;
    this.rangeRing.scale.setScalar(r);
    this.rangeDisc.scale.setScalar(r);
    const col = ok ? 0x80ffff : 0xff6060;
    this.rangeRing.material.color.setHex(col);
    this.rangeDisc.material.color.setHex(col);
  }

  // ------------------------------------------------------------- DEKORACJE (zależne od jakości)
  buildDecor(qualityDef) {
    // usuń poprzednie
    for (const c of [...this.decor.children]) { this.decor.remove(c); c.geometry?.dispose(); }
    const rnd = mulberry32(99);
    const outside = (x, z, m = 3) => Math.abs(z) > MAP.halfD + m || Math.abs(x) > MAP.halfW + m;

    // --- drzewa: świerki i martwe drzewa
    const pine = mergeGeometries([
      paint(place(new THREE.CylinderGeometry(0.18, 0.28, 1.6, 6), 0, 0.8, 0), 0x4a3424),
      paint(place(new THREE.ConeGeometry(1.5, 2.4, 7), 0, 2.2, 0), 0x2c4a2a),
      paint(place(new THREE.ConeGeometry(1.15, 2.0, 7), 0, 3.3, 0), 0x335530),
      paint(place(new THREE.ConeGeometry(0.75, 1.6, 7), 0, 4.3, 0), 0x3b6036),
    ]);
    const dead = mergeGeometries([
      paint(place(new THREE.CylinderGeometry(0.12, 0.26, 3.6, 5), 0, 1.8, 0), 0x3d3128),
      paint(place(new THREE.CylinderGeometry(0.05, 0.1, 1.6, 4), 0.45, 2.6, 0, 0, 0, -0.9), 0x3d3128),
      paint(place(new THREE.CylinderGeometry(0.05, 0.1, 1.3, 4), -0.4, 3.0, 0.1, 0.2, 0, 0.8), 0x3d3128),
      paint(place(new THREE.CylinderGeometry(0.04, 0.08, 1.0, 4), 0.1, 3.4, -0.35, -0.9, 0, 0), 0x3d3128),
    ]);
    const treeMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.9, flatShading: true });
    const nTrees = qualityDef.trees;
    const pines = new THREE.InstancedMesh(pine, treeMat, nTrees);
    const deads = new THREE.InstancedMesh(dead, treeMat, Math.ceil(nTrees / 3));
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3(), e = new THREE.Euler();
    let pi = 0, di = 0, guard = 0;
    while ((pi < pines.count || di < deads.count) && guard++ < 20000) {
      const x = (rnd() - 0.5) * (MAP.width + 120), z = (rnd() - 0.5) * (MAP.depth + 110);
      if (!outside(x, z, 4)) continue;
      const y = this.heightAt(x, z);
      const sc = 0.8 + rnd() * 1.1;
      e.set((rnd() - 0.5) * 0.1, rnd() * Math.PI * 2, (rnd() - 0.5) * 0.1);
      m.compose(p.set(x, y - 0.1, z), q.setFromEuler(e), s.set(sc, sc * (0.85 + rnd() * 0.4), sc));
      if (rnd() < 0.72 && pi < pines.count) pines.setMatrixAt(pi++, m);
      else if (di < deads.count) deads.setMatrixAt(di++, m);
    }
    pines.count = pi; deads.count = di;
    for (const t of [pines, deads]) { t.castShadow = true; t.receiveShadow = true; this.decor.add(t); }

    // --- skały
    const rockMat = new THREE.MeshStandardMaterial({ color: 0x77736a, roughness: 0.95, flatShading: true });
    const rocks = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(1, 0), rockMat, 90);
    for (let i = 0; i < rocks.count; i++) {
      let x, z;
      do { x = (rnd() - 0.5) * (MAP.width + 80); z = (rnd() - 0.5) * (MAP.depth + 70); } while (!outside(x, z, 2));
      const sc = 0.4 + rnd() * 1.4;
      e.set(rnd() * 3, rnd() * 3, rnd() * 3);
      m.compose(p.set(x, this.heightAt(x, z) + sc * 0.2, z), q.setFromEuler(e), s.set(sc * (1 + rnd()), sc * 0.7, sc));
      rocks.setMatrixAt(i, m);
    }
    rocks.castShadow = rocks.receiveShadow = true;
    this.decor.add(rocks);

    // --- trawa z wiatrem (shader)
    this.grassMat = null;
    if (qualityDef.grass > 0) {
      const blades = [];
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        blades.push(place(new THREE.ConeGeometry(0.07, 0.6 + (i % 3) * 0.15, 3), Math.cos(a) * 0.12, 0.3, Math.sin(a) * 0.12, Math.cos(a) * 0.25, 0, Math.sin(a) * 0.25));
      }
      const grassGeo = mergeGeometries(blades);
      const grassMat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1 });
      const uniforms = { uTime: { value: 0 } };
      grassMat.onBeforeCompile = (sh) => {
        sh.uniforms.uTime = uniforms.uTime;
        sh.vertexShader = 'uniform float uTime;\n' + sh.vertexShader.replace('#include <begin_vertex>', `
          #include <begin_vertex>
          #ifdef USE_INSTANCING
            vec2 ip = vec2(instanceMatrix[3].x, instanceMatrix[3].z);
            float sway = sin(uTime * 1.8 + ip.x * 0.35 + ip.y * 0.21) + 0.5 * sin(uTime * 3.1 + ip.x * 0.9);
            transformed.x += sway * 0.09 * position.y * position.y * 3.0;
            transformed.z += cos(uTime * 1.3 + ip.y * 0.4) * 0.04 * position.y;
          #endif`);
      };
      this.grassUniforms = uniforms;
      const grass = new THREE.InstancedMesh(grassGeo, grassMat, qualityDef.grass);
      const col = new THREE.Color();
      for (let i = 0; i < grass.count; i++) {
        let x, z, tries = 0;
        do {
          x = (rnd() - 0.5) * (MAP.width + 30); z = (rnd() - 0.5) * (MAP.depth + 24);
          tries++;
        } while (tries < 10 && (Math.abs(z + Math.sin(x * 0.07) * 3.5) < 4 || Math.hypot(x - MAP.baseX, z) < 9 || Math.hypot(x - MAP.spawnX, z) < 12));
        const sc = 0.7 + rnd() * 0.9;
        m.compose(p.set(x, this.heightAt(x, z), z), q.setFromEuler(e.set(0, rnd() * 6.28, 0)), s.set(sc, sc * (0.7 + rnd() * 0.8), sc));
        grass.setMatrixAt(i, m);
        col.setHSL(0.18 + rnd() * 0.07, 0.5 + rnd() * 0.2, 0.26 + rnd() * 0.12);
        grass.setColorAt(i, col);
      }
      grass.receiveShadow = true;
      this.decor.add(grass);
    }

    // --- płonące beczki (pozycje do efektów)
    this.fires = [
      new THREE.Vector3(MAP.baseX - 9, 0, -9), new THREE.Vector3(MAP.baseX - 9, 0, 9),
      new THREE.Vector3(MAP.baseX - 26, 0, -MAP.halfD + 2.5), new THREE.Vector3(MAP.baseX - 26, 0, MAP.halfD - 2.5),
    ];
    const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.42, 1.1, 10),
      new THREE.MeshStandardMaterial({ color: 0x4a3a30, metalness: 0.6, roughness: 0.6 }));
    for (const f of this.fires) {
      const b = barrel.clone(); b.position.set(f.x, 0.55, f.z); b.castShadow = true; this.decor.add(b);
    }
  }

  update(dt) {
    this.time += dt;
    const t = this.time;
    if (this.grassUniforms) this.grassUniforms.uTime.value = t;

    // flaga
    const pos = this.flag.geometry.attributes.position;
    const b = this.flagBase;
    for (let i = 0; i < pos.count; i++) {
      const x = b[i * 3];
      pos.array[i * 3 + 2] = Math.sin(x * 2.6 - t * 5) * 0.18 * x + Math.sin(x * 4 - t * 7) * 0.05 * x;
      pos.array[i * 3 + 1] = b[i * 3 + 1] - x * 0.05 + Math.sin(x * 3 - t * 4) * 0.03 * x;
    }
    pos.needsUpdate = true;
    this.flag.geometry.computeVertexNormals();

    this.torch.intensity = 26 + Math.sin(t * 13) * 4 + Math.sin(t * 31) * 3;
    this.spawnLight.intensity = 34 + Math.sin(t * 2) * 10;
    this.portal.material.opacity = 0.4 + Math.sin(t * 2.2) * 0.12;
    for (const r of this.slotRings) { r.material.opacity = 0.5 + Math.sin(t * 3) * 0.3; r.rotation.z = t * 0.5; }

    if (this.cageState === 'opening') {
      this.cage.position.y -= dt * 3.5;
      if (this.cage.position.y < -7) { this.cageState = 'open'; this.cage.visible = false; }
    }
  }
}
