// =====================================================================
//  INSTANCED RIG - animowane postacie złożone z części (InstancedMesh)
//  Każda część (głowa, ręka, noga...) wszystkich postaci danego typu
//  to JEDNO wywołanie rysowania - setki zombie bez spadku FPS.
// =====================================================================
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { place } from './utils.js';

const _root = new THREE.Matrix4();
const _local = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler(0, 0, 0, 'YXZ');
const _p = new THREE.Vector3();
const _s = new THREE.Vector3();
const _one = new THREE.Vector3(1, 1, 1);
const _zero = new THREE.Matrix4().makeScale(0, 0, 0);
const _c = new THREE.Color();
const WHITE = new THREE.Color(1, 1, 1);
const ZERO3 = [0, 0, 0];

/**
 * part: { geo, mat, pivot:[x,y,z], parent?:index, rot?:(e)=>[x,y,z], slide?:(e)=>z,
 *         show?:(e)=>bool, tint?:'skin'|'cloth'|..., shadow?:bool }
 */
export class InstancedRig {
  constructor(scene, parts, capacity) {
    this.capacity = capacity;
    this.parts = parts.map((p) => {
      const mesh = new THREE.InstancedMesh(p.geo, p.mat, capacity);
      mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      mesh.count = 0;
      mesh.frustumCulled = false;
      mesh.castShadow = p.shadow !== false;
      mesh.receiveShadow = false;
      if (p.tint) {
        mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(capacity * 3).fill(1), 3);
        mesh.instanceColor.setUsage(THREE.DynamicDrawUsage);
      }
      scene.add(mesh);
      return { ...p, mesh };
    });
    this._world = this.parts.map(() => new THREE.Matrix4());
  }

  update(list) {
    const n = Math.min(list.length, this.capacity);
    const parts = this.parts;
    for (const p of parts) p.mesh.count = n;
    for (let i = 0; i < n; i++) {
      const e = list[i];
      _e.set(e.tilt || 0, e.rot || 0, e.roll || 0);
      _root.compose(_p.set(e.x, e.y || 0, e.z), _q.setFromEuler(_e), _s.setScalar(e.scale || 1));
      for (let k = 0; k < parts.length; k++) {
        const part = parts[k];
        const W = this._world[k];
        if (part.show && !part.show(e)) { part.mesh.setMatrixAt(i, _zero); W.copy(_zero); continue; }
        const r = part.rot ? part.rot(e) : ZERO3;
        _e.set(r[0], r[1], r[2]);
        const pv = part.pivot;
        _local.compose(_p.set(pv[0], pv[1], pv[2] + (part.slide ? part.slide(e) : 0)), _q.setFromEuler(_e), _one);
        W.multiplyMatrices(part.parent !== undefined ? this._world[part.parent] : _root, _local);
        part.mesh.setMatrixAt(i, W);
        if (part.tint) {
          _c.copy(e[part.tint] || WHITE);
          if (e.flash > 0) _c.lerp(WHITE, Math.min(0.6, e.flash * 0.6));
          part.mesh.setColorAt(i, _c);
        }
      }
    }
    for (const p of parts) {
      p.mesh.instanceMatrix.needsUpdate = true;
      if (p.mesh.instanceColor) p.mesh.instanceColor.needsUpdate = true;
    }
  }

  setShadows(on) { for (const p of this.parts) p.mesh.castShadow = on && p.shadow !== false; }
}

// ---------------------------------------------------------------------
//  MODELE
// ---------------------------------------------------------------------
const flatWhite = () => new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.85, flatShading: true });
const glowMat = (r, g, b) => new THREE.MeshBasicMaterial({ color: new THREE.Color(r, g, b), toneMapped: false });

export function createZombieRig(scene, capacity) {
  const skinMat = flatWhite(), clothMat = flatWhite();
  const torso = place(new THREE.BoxGeometry(0.7, 0.85, 0.4), 0, 0.43, 0);
  const head = place(new THREE.IcosahedronGeometry(0.28, 1), 0, 0.26, 0.04, 0, 0, 0, 1, 1.08, 1);
  const eyes = mergeGeometries([
    place(new THREE.BoxGeometry(0.08, 0.06, 0.04), -0.1, 0.3, 0.27),
    place(new THREE.BoxGeometry(0.08, 0.06, 0.04), 0.1, 0.3, 0.27),
  ]);
  const arm = place(new THREE.BoxGeometry(0.17, 0.78, 0.19), 0, -0.36, 0);
  const leg = place(new THREE.BoxGeometry(0.24, 0.95, 0.26), 0, -0.47, 0);
  const crown = mergeGeometries([
    place(new THREE.CylinderGeometry(0.3, 0.26, 0.14, 8, 1, true), 0, 0.55, 0.03),
    ...[0, 1, 2, 3, 4].map(i => place(new THREE.ConeGeometry(0.06, 0.18, 4), Math.cos(i * 1.256) * 0.28, 0.69, 0.03 + Math.sin(i * 1.256) * 0.28)),
  ].map(g => g.index ? g.toNonIndexed() : g));
  const crownMat = new THREE.MeshStandardMaterial({ color: 0xffc23a, metalness: 0.9, roughness: 0.3, emissive: 0x553300, side: THREE.DoubleSide });

  return new InstancedRig(scene, [
    /*0*/ { geo: torso, mat: clothMat, pivot: [0, 0.95, 0], rot: e => [e.hunch, 0, e.sway], tint: 'cloth' },
    /*1*/ { geo: head, mat: skinMat, pivot: [0, 0.86, 0.05], parent: 0, rot: e => [e.headTilt, e.headYaw, e.sway * 2], tint: 'skin' },
    /*2*/ { geo: eyes, mat: glowMat(5, 0.4, 0.15), pivot: [0, 0, 0], parent: 1, shadow: false },
    /*3*/ { geo: arm, mat: skinMat, pivot: [-0.45, 0.78, 0], parent: 0, rot: e => [e.armL, 0, 0.12], tint: 'skin' },
    /*4*/ { geo: arm, mat: skinMat, pivot: [0.45, 0.78, 0], parent: 0, rot: e => [e.armR, 0, -0.12], tint: 'skin' },
    /*5*/ { geo: leg, mat: clothMat, pivot: [-0.18, 0.95, 0], rot: e => [e.legL, 0, 0], tint: 'pants' },
    /*6*/ { geo: leg, mat: clothMat, pivot: [0.18, 0.95, 0], rot: e => [e.legR, 0, 0], tint: 'pants' },
    /*7*/ { geo: crown, mat: crownMat, pivot: [0, 0, 0], parent: 1, show: e => e.isBoss, shadow: false },
  ], capacity);
}

export function createSoldierRig(scene, capacity) {
  const cloth = flatWhite();
  const skin = new THREE.MeshStandardMaterial({ color: 0xe0b48c, roughness: 0.8, flatShading: true });
  const dark = new THREE.MeshStandardMaterial({ color: 0x1e1e1e, roughness: 0.5, metalness: 0.5 });
  const helmetMat = new THREE.MeshStandardMaterial({ color: 0x3d4a2a, roughness: 0.7, flatShading: true });
  const torso = mergeGeometries([
    place(new THREE.BoxGeometry(0.62, 0.75, 0.36), 0, 0.38, 0),
    place(new THREE.BoxGeometry(0.66, 0.35, 0.42), 0, 0.5, 0), // kamizelka
  ]);
  const head = place(new THREE.BoxGeometry(0.34, 0.36, 0.34), 0, 0.2, 0);
  const helmet = mergeGeometries([
    place(new THREE.SphereGeometry(0.25, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), 0, 0.32, 0, 0, 0, 0, 1.05, 0.9, 1.1),
    place(new THREE.CylinderGeometry(0.3, 0.3, 0.04, 12), 0, 0.32, 0),
  ].map(g => g.index ? g.toNonIndexed() : g));
  const arm = place(new THREE.BoxGeometry(0.15, 0.65, 0.17), 0, -0.3, 0);
  const leg = place(new THREE.BoxGeometry(0.22, 0.9, 0.24), 0, -0.45, 0);
  const rifle = mergeGeometries([
    place(new THREE.BoxGeometry(0.08, 0.13, 0.75), 0, 0, 0.2),
    place(new THREE.BoxGeometry(0.05, 0.05, 0.5), 0, 0.02, 0.8),
    place(new THREE.BoxGeometry(0.07, 0.2, 0.1), 0, -0.13, 0.1),
  ]);
  return new InstancedRig(scene, [
    /*0*/ { geo: torso, mat: cloth, pivot: [0, 0.9, 0], rot: e => [e.hunch || 0.05, 0, 0], tint: 'cloth' },
    /*1*/ { geo: head, mat: skin, pivot: [0, 0.78, 0], parent: 0 },
    /*2*/ { geo: helmet, mat: helmetMat, pivot: [0, 0, 0], parent: 1 },
    /*3*/ { geo: arm, mat: cloth, pivot: [-0.38, 0.68, 0], parent: 0, rot: () => [-1.25, 0, 0.55], tint: 'cloth' },
    /*4*/ { geo: arm, mat: cloth, pivot: [0.38, 0.68, 0], parent: 0, rot: () => [-1.45, 0, -0.1], tint: 'cloth' },
    /*5*/ { geo: rifle, mat: dark, pivot: [0.12, 0.55, 0.3], parent: 0, slide: e => -e.recoil * 0.25 },
    /*6*/ { geo: leg, mat: cloth, pivot: [-0.16, 0.9, 0], rot: e => [e.legL, 0, 0], tint: 'pants' },
    /*7*/ { geo: leg, mat: cloth, pivot: [0.16, 0.9, 0], rot: e => [e.legR, 0, 0], tint: 'pants' },
  ], capacity);
}

export function createTankRig(scene, capacity) {
  const body = flatWhite();
  const dark = new THREE.MeshStandardMaterial({ color: 0x222222, roughness: 0.9, flatShading: true });
  const hull = mergeGeometries([
    place(new THREE.BoxGeometry(1.7, 0.6, 2.5), 0, 0.75, 0),
    place(new THREE.BoxGeometry(1.5, 0.3, 0.6), 0, 0.7, 1.4, -0.5),
  ]);
  const tracks = mergeGeometries([
    place(new THREE.BoxGeometry(0.45, 0.6, 2.8), -0.95, 0.35, 0),
    place(new THREE.BoxGeometry(0.45, 0.6, 2.8), 0.95, 0.35, 0),
  ]);
  const turret = mergeGeometries([
    place(new THREE.CylinderGeometry(0.62, 0.72, 0.5, 8), 0, 0.25, 0),
    place(new THREE.BoxGeometry(0.5, 0.25, 0.4), 0, 0.3, -0.7),
  ].map(g => g.toNonIndexed()));
  const barrel = place(new THREE.CylinderGeometry(0.09, 0.11, 1.7, 8), 0, 0, 0.85, Math.PI / 2);
  return new InstancedRig(scene, [
    /*0*/ { geo: hull, mat: body, pivot: [0, 0, 0], rot: e => [e.hunch || 0, 0, 0], tint: 'cloth' },
    /*1*/ { geo: tracks, mat: dark, pivot: [0, 0, 0] },
    /*2*/ { geo: turret, mat: body, pivot: [0, 1.05, -0.1], parent: 0, rot: e => [0, e.turret || 0, 0], tint: 'cloth' },
    /*3*/ { geo: barrel, mat: dark, pivot: [0, 0.3, 0.45], parent: 2, slide: e => -e.recoil * 0.4 },
  ], capacity);
}
