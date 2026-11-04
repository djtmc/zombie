// =====================================================================
//  STEROWANIE: przeciąganie mapy (z bezwładnością), zoom, pinch, klawisze
// =====================================================================
import * as THREE from 'three';
import { BUILDINGS, BUILD_ORDER } from './config.js';

const DRAG_PX = 7;

export class Input {
  constructor(dom, rig, camera, game, handlers) {
    this.dom = dom; this.rig = rig; this.camera = camera; this.game = game; this.h = handlers;
    this.ray = new THREE.Raycaster();
    this.plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    this._ndc = new THREE.Vector2();
    this._hit = new THREE.Vector3();
    this.pointers = new Map();
    this.keys = new Set();
    this.vel = 0;
    this.enabled = true;

    dom.addEventListener('pointerdown', (e) => this._down(e));
    addEventListener('pointermove', (e) => this._move(e));
    addEventListener('pointerup', (e) => this._up(e));
    addEventListener('pointercancel', (e) => this._up(e, true));
    dom.addEventListener('wheel', (e) => { e.preventDefault(); this.rig.setZoom(this.rig.targetZoom * (1 + Math.sign(e.deltaY) * 0.1)); }, { passive: false });
    dom.addEventListener('contextmenu', (e) => e.preventDefault());
    addEventListener('keydown', (e) => this._key(e, true));
    addEventListener('keyup', (e) => this._key(e, false));
    addEventListener('blur', () => this.keys.clear());
  }

  groundPoint(cx, cy) {
    this._ndc.set((cx / innerWidth) * 2 - 1, -(cy / innerHeight) * 2 + 1);
    this.ray.setFromCamera(this._ndc, this.camera);
    return this.ray.ray.intersectPlane(this.plane, this._hit);
  }

  _down(e) {
    if (!this.enabled) return;
    this.h.unlockAudio();
    this.dom.setPointerCapture?.(e.pointerId);
    this.pointers.set(e.pointerId, { x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, type: e.pointerType, button: e.button, t: performance.now() });
    this.vel = 0;
    if (this.pointers.size === 2) {
      const [a, b] = [...this.pointers.values()];
      this.pinch = { d: Math.hypot(a.x - b.x, a.y - b.y), zoom: this.rig.targetZoom };
      for (const p of this.pointers.values()) p.moved = true; // pinch to nie kliknięcie
    }
  }

  _move(e) {
    const p = this.pointers.get(e.pointerId);
    if (!p) {
      // ruch myszy bez wciśnięcia - podgląd budynku
      if (e.pointerType === 'mouse' && e.target === this.dom) {
        const g = this.groundPoint(e.clientX, e.clientY);
        if (g) this.game.pointerMove(g.x, g.z);
      }
      return;
    }
    const dx = e.clientX - p.x;
    p.x = e.clientX; p.y = e.clientY;
    if (this.pointers.size === 2 && this.pinch) {
      const [a, b] = [...this.pointers.values()];
      const d = Math.hypot(a.x - b.x, a.y - b.y);
      this.rig.setZoom(this.pinch.zoom * this.pinch.d / Math.max(20, d));
      return;
    }
    if (!p.moved && Math.hypot(e.clientX - p.sx, e.clientY - p.sy) > DRAG_PX) {
      p.moved = true;
      this.dom.parentElement.classList.add('dragging');
    }
    if (p.moved) {
      const k = this.rig.unitsPerPixel() * 1.25;
      this.rig.pan(-dx * k);
      const now = performance.now();
      const dt = Math.max(1, now - p.t) / 1000;
      this.vel = this.vel * 0.6 + (-dx * k / dt) * 0.4;
      p.t = now;
    } else if (p.type === 'mouse') {
      const g = this.groundPoint(e.clientX, e.clientY);
      if (g) this.game.pointerMove(g.x, g.z);
    }
  }

  _up(e, cancel = false) {
    const p = this.pointers.get(e.pointerId);
    if (!p) return;
    this.pointers.delete(e.pointerId);
    if (this.pointers.size < 2) this.pinch = null;
    this.dom.parentElement.classList.remove('dragging');
    if (performance.now() - p.t > 80) this.vel = 0; // zatrzymany palec = bez bezwładności
    if (cancel || p.moved || !this.enabled) return;
    if (p.button === 2) { this.game.cancelBuild(); this.game.deselect(); return; }
    const g = this.groundPoint(e.clientX, e.clientY);
    if (g) this.game.pointerTap(g.x, g.z, p.type !== 'mouse');
  }

  _key(e, down) {
    if (e.target && (e.target.tagName === 'INPUT')) return;
    const k = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    if (down) this.keys.add(k); else this.keys.delete(k);
    if (!down || e.repeat) return;
    if (k === 'Escape') { this.h.escape(); return; }
    if (!this.enabled) return;
    if (k === 'p' || k === ' ') { e.preventDefault(); this.h.togglePause(); return; }
    if (k === 'f') this.h.toggleSpeed();
    if (k === 'm') this.h.toggleSound();
    if (k === 'n') this.game.callWaveEarly();
    const idx = BUILD_ORDER.findIndex(t => BUILDINGS[t].key === k);
    if (idx >= 0) this.game.selectBuild(BUILD_ORDER[idx]);
  }

  update(dt) {
    if (!this.enabled) { this.vel = 0; return; }
    const sp = 45 * this.rig.zoom * dt;
    if (this.keys.has('a') || this.keys.has('ArrowLeft')) this.rig.pan(-sp);
    if (this.keys.has('d') || this.keys.has('ArrowRight')) this.rig.pan(sp);
    if (this.keys.has('w') || this.keys.has('ArrowUp') || this.keys.has('+') || this.keys.has('=')) this.rig.setZoom(this.rig.targetZoom * (1 - dt * 1.2));
    if (this.keys.has('s') || this.keys.has('ArrowDown') || this.keys.has('-')) this.rig.setZoom(this.rig.targetZoom * (1 + dt * 1.2));
    // bezwładność przeciągania
    if (this.pointers.size === 0 && Math.abs(this.vel) > 0.5) {
      this.rig.pan(this.vel * dt);
      this.vel *= Math.exp(-dt * 4);
    }
  }
}
