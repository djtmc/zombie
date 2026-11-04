// =====================================================================
//  MODELE BUDYNKÓW (niski poligon, łączone geometrie z kolorami wierzchołków)
// =====================================================================
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { paint, place } from './utils.js';

const vcMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.85, flatShading: true });
const metalMat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.4, metalness: 0.75, flatShading: true });
const ghostOk = new THREE.MeshBasicMaterial({ color: 0x60ff90, transparent: true, opacity: 0.45, depthWrite: false });
const ghostBad = new THREE.MeshBasicMaterial({ color: 0xff4040, transparent: true, opacity: 0.45, depthWrite: false });

const C = {
  wood: 0x7a5534, woodDark: 0x4e3622, plank: 0x9a7048, stone: 0x8c877c, stoneDark: 0x5f5b54,
  metal: 0x3c3f44, metalLight: 0x7b8088, roofRed: 0x8a2a22, roofGrey: 0x4a4f55, olive: 0x4b5a2e,
  gold: 0xffc93a, brick: 0x8a4a3a,
};

function M(parts, mat = vcMat) {
  const g = mergeGeometries(parts.map(p => p.index ? p.toNonIndexed() : p));
  const mesh = new THREE.Mesh(g, mat);
  mesh.castShadow = mesh.receiveShadow = true;
  return mesh;
}
const B = (w, h, d, x, y, z, col, rx = 0, ry = 0, rz = 0) => paint(place(new THREE.BoxGeometry(w, h, d), x, y, z, rx, ry, rz), col);
const CY = (r1, r2, h, x, y, z, col, seg = 10, rx = 0, ry = 0, rz = 0) => paint(place(new THREE.CylinderGeometry(r1, r2, h, seg), x, y, z, rx, ry, rz), col);
const CO = (r, h, x, y, z, col, seg = 8, ry = 0) => paint(place(new THREE.ConeGeometry(r, h, seg), x, y, z, 0, ry), col);

export function createBuildingMesh(type) {
  const g = new THREE.Group();
  const anim = {};
  let muzzle = null;

  switch (type) {
    case 'wall': { // zasieki: skrzyżowane, zaostrzone pale + drut
      const parts = [];
      for (let i = 0; i < 3; i++) { // "jeż": trzy pochylone, zaostrzone pale
        const beam = paint(place(new THREE.CylinderGeometry(0.05, 0.12, 2.6, 5), 0, 0.8, 0, 0, 0, 0.95), C.wood);
        beam.rotateY(i * Math.PI * 2 / 3);
        parts.push(beam);
      }
      parts.push(B(1.9, 0.12, 0.12, 0, 0.35, 0, C.woodDark));
      parts.push(B(0.12, 0.12, 1.9, 0, 0.35, 0, C.woodDark));
      g.add(M(parts));
      const wire = new THREE.Mesh(new THREE.TorusGeometry(0.75, 0.025, 4, 24), new THREE.MeshStandardMaterial({ color: 0x9a9a9a, metalness: 0.9, roughness: 0.3 }));
      wire.rotation.x = Math.PI / 2; wire.position.y = 0.9; g.add(wire);
      break;
    }
    case 'bigwall': {
      const parts = [B(3, 3.2, 1.6, 0, 1.6, 0, C.stone)];
      for (const x of [-1.1, 0, 1.1]) parts.push(B(0.7, 0.6, 1.7, x, 3.5, 0, C.stone));
      for (let i = 0; i < 6; i++) parts.push(B(0.6 + Math.random() * 0.4, 0.4, 0.05, -1.1 + (i % 3) * 1.1, 0.6 + Math.floor(i / 3) * 1.3, 0.81, C.stoneDark));
      parts.push(B(3.3, 0.4, 1.9, 0, 0.2, 0, C.stoneDark));
      g.add(M(parts));
      break;
    }
    case 'cannon': {
      g.add(M([CY(1.0, 1.15, 0.6, 0, 0.3, 0, C.woodDark, 10), B(1.5, 0.15, 1.5, 0, 0.65, 0, C.plank)]));
      const turret = new THREE.Group(); turret.position.y = 0.75;
      turret.add(M([B(0.35, 0.6, 1.2, -0.45, 0.3, 0, C.wood), B(0.35, 0.6, 1.2, 0.45, 0.3, 0, C.wood),
        CY(0.35, 0.35, 0.1, -0.65, 0.2, 0.3, C.woodDark, 10, 0, 0, Math.PI / 2), CY(0.35, 0.35, 0.1, 0.65, 0.2, 0.3, C.woodDark, 10, 0, 0, Math.PI / 2)]));
      const barrel = M([CY(0.22, 0.3, 1.8, 0, 0, 0.5, C.metal, 12, Math.PI / 2), CY(0.27, 0.27, 0.15, 0, 0, 1.35, C.metalLight, 12, Math.PI / 2),
        CY(0.32, 0.32, 0.4, 0, 0, -0.4, C.metal, 12, Math.PI / 2)], metalMat);
      barrel.position.y = 0.6; barrel.rotation.x = -0.15;
      turret.add(barrel);
      g.add(turret);
      anim.turret = turret; anim.barrel = barrel; anim.barrelZ = 0;
      muzzle = new THREE.Vector3(0, 1.5, 1.4);
      break;
    }
    case 'wielkaArmata': {
      g.add(M([CY(1.7, 1.9, 0.8, 0, 0.4, 0, C.stoneDark, 10), CY(1.5, 1.5, 0.3, 0, 0.95, 0, C.metal, 16)], metalMat));
      const turret = new THREE.Group(); turret.position.y = 1.1;
      turret.add(M([B(2.2, 1.3, 2.2, 0, 0.65, -0.2, C.olive), B(0.4, 0.9, 1.4, -1.1, 1.1, 0, C.olive), B(0.4, 0.9, 1.4, 1.1, 1.1, 0, C.olive),
        B(1.6, 0.4, 0.6, 0, 1.4, -1.1, C.metal)]));
      const barrel = M([CY(0.38, 0.5, 4.2, 0, 0, 1.6, C.metal, 14, Math.PI / 2), CY(0.5, 0.5, 0.5, 0, 0, 3.6, C.metalLight, 14, Math.PI / 2),
        CY(0.45, 0.45, 0.3, 0, 0, 3.95, C.metal, 14, Math.PI / 2)], metalMat);
      barrel.position.y = 1.2; barrel.rotation.x = -0.12;
      turret.add(barrel);
      g.add(turret);
      anim.turret = turret; anim.barrel = barrel; anim.barrelZ = 0;
      muzzle = new THREE.Vector3(0, 2.8, 4.1);
      break;
    }
    case 'koszary': {
      g.add(M([
        B(4, 0.3, 3.4, 0, 0.15, 0, C.stoneDark),
        B(3.6, 2.4, 3, 0, 1.5, 0, C.olive),
        B(3.9, 0.25, 3.3, 0, 2.8, 0, C.woodDark),
        B(1, 1.5, 0.1, 0, 1.05, 1.52, C.woodDark),
        B(0.7, 0.45, 0.1, -1.2, 1.8, 1.52, 0x222222), B(0.7, 0.45, 0.1, 1.2, 1.8, 1.52, 0x222222),
        ...[-1.2, 0, 1.2].map(x => B(0.9, 0.5, 0.9, x, 0.25, -1.9, 0xb59a6a)), // worki z piaskiem
      ]));
      const roof = M([CO(2.9, 1.6, 0, 3.7, 0, C.roofGrey, 4, Math.PI / 4)]);
      roof.scale.set(1.2, 1, 1); g.add(roof);
      g.add(M([CY(0.05, 0.05, 2.2, 1.6, 4.0, 1.2, 0x333333, 6)], metalMat));
      const flag = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.55), new THREE.MeshStandardMaterial({ color: 0x55702e, side: THREE.DoubleSide }));
      flag.geometry.translate(0.45, 0, 0);
      flag.position.set(1.6, 4.8, 1.2); g.add(flag);
      anim.flag = flag;
      break;
    }
    case 'factory': {
      g.add(M([
        B(4.2, 0.3, 3.4, 0, 0.15, 0, C.stoneDark),
        B(3.8, 2.6, 3, 0, 1.6, 0, C.brick),
        ...[-1.25, 0, 1.25].map(x => paint(place(new THREE.BoxGeometry(1.25, 0.9, 3.1), x, 3.15, 0, 0, 0, 0.45), C.roofGrey)),
        B(1.8, 1.7, 0.1, 0, 1.15, 1.52, C.metal),
        ...[-1.3, 1.3].map(x => B(0.6, 0.6, 0.1, x, 2, 1.52, 0xffaa44)),
      ]));
      g.add(M([CY(0.35, 0.45, 3.2, 1.3, 4.2, -0.8, C.brick, 8), CY(0.42, 0.42, 0.25, 1.3, 5.8, -0.8, C.metal, 8)]));
      const glow = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.5, 0.05), new THREE.MeshBasicMaterial({ color: new THREE.Color(3, 1.4, 0.3), toneMapped: false }));
      glow.position.set(0, 0.5, 1.56); g.add(glow);
      anim.chimney = new THREE.Vector3(1.3, 6.1, -0.8);
      break;
    }
    case 'sawmill': {
      g.add(M([
        B(3, 0.25, 2.4, 0, 0.12, 0, C.woodDark),
        B(2.6, 1.8, 2, 0, 1.15, -0.1, C.plank),
        paint(place(new THREE.BoxGeometry(1.6, 0.12, 2.3), -0.6, 2.35, -0.1, 0, 0, 0.5), C.woodDark),
        paint(place(new THREE.BoxGeometry(1.6, 0.12, 2.3), 0.6, 2.35, -0.1, 0, 0, -0.5), C.woodDark),
        ...[0, 1, 2].map(i => CY(0.22, 0.22, 2.2, 1.6, 0.25 + (i === 2 ? 0.38 : 0), -0.4 + (i === 2 ? 0.22 : i * 0.44), C.wood, 8, Math.PI / 2, 0, 0)),
        B(1.4, 0.7, 0.7, -0.3, 0.6, 1.2, C.woodDark),
      ]));
      const saw = new THREE.Mesh(new THREE.CylinderGeometry(0.6, 0.6, 0.06, 18), new THREE.MeshStandardMaterial({ color: 0xcfd4da, metalness: 0.9, roughness: 0.2 }));
      saw.rotation.z = Math.PI / 2; saw.position.set(-0.3, 1.05, 1.2);
      const sawPivot = new THREE.Group(); sawPivot.add(saw); g.add(sawPivot);
      anim.saw = saw;
      anim.dust = new THREE.Vector3(-0.3, 1.1, 1.5);
      break;
    }
    case 'mine': {
      g.add(M([
        paint(place(new THREE.DodecahedronGeometry(1.5, 0), 0, 0.8, -0.3, 0, 0, 0, 1.2, 0.8, 1), C.stoneDark),
        B(1.1, 1.2, 0.2, 0, 0.6, 0.85, 0x151210),
        B(0.18, 1.5, 0.18, -0.65, 0.75, 0.9, C.wood), B(0.18, 1.5, 0.18, 0.65, 0.75, 0.9, C.wood), B(1.5, 0.18, 0.2, 0, 1.5, 0.9, C.wood),
        ...[-0.4, 0.4].map(x => B(0.08, 0.05, 1.4, x, 0.05, 1.5, C.metal)),
        B(0.8, 0.5, 0.9, 0.9, 0.35, 1.3, C.metal),
        B(0.16, 2.8, 0.16, -0.9, 1.4, -0.4, C.woodDark), B(0.16, 2.8, 0.16, 0.9, 1.4, -0.4, C.woodDark),
        B(2, 0.16, 0.16, 0, 2.8, -0.4, C.woodDark),
      ]));
      const ore = new THREE.Mesh(new THREE.DodecahedronGeometry(0.3, 0), new THREE.MeshStandardMaterial({ color: 0xffd040, emissive: 0xffaa00, emissiveIntensity: 1.4, metalness: 0.8, roughness: 0.3 }));
      ore.position.set(0.9, 0.75, 1.3); g.add(ore);
      const wheel = new THREE.Mesh(new THREE.TorusGeometry(0.6, 0.08, 6, 16), new THREE.MeshStandardMaterial({ color: 0x3a3a3a, metalness: 0.8, roughness: 0.4 }));
      wheel.position.set(0, 2.8, -0.25); g.add(wheel);
      anim.wheel = wheel;
      break;
    }
  }

  g.traverse(o => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  return { group: g, anim, muzzle };
}

/** Półprzezroczysty "duch" budynku do podglądu przy stawianiu */
export function createGhost(type) {
  if (type === 'soldier') {
    const g = new THREE.Group();
    const m = new THREE.Mesh(new THREE.CapsuleGeometry(0.35, 1.1, 4, 8), ghostOk);
    m.position.y = 0.95; g.add(m);
    return g;
  }
  const { group } = createBuildingMesh(type);
  group.traverse(o => { if (o.isMesh) { o.material = ghostOk; o.castShadow = false; o.receiveShadow = false; } });
  return group;
}
export function setGhostOk(ghost, ok) {
  const mat = ok ? ghostOk : ghostBad;
  ghost.traverse(o => { if (o.isMesh) o.material = mat; });
}
