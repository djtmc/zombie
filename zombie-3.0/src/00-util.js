// Narzędzia wspólne: losowość z ziarnem, matematyka, kolory.
const TAU = Math.PI * 2;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = t => t * t * (3 - 2 * t);
const dist2 = (ax, az, bx, bz) => { const dx = ax - bx, dz = az - bz; return dx * dx + dz * dz; };

function mulberry(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}
let rnd = mulberry((Math.random() * 1e9) | 0);
const rr = (a, b) => a + (b - a) * rnd();
const ri = (a, b) => Math.floor(rr(a, b + 1));
const pick = arr => arr[Math.floor(rnd() * arr.length)];
const chance = p => rnd() < p;

function col(hex) { return new THREE.Color(hex); }
function shade(hex, f) { const c = new THREE.Color(hex); c.multiplyScalar(f); return c; }
function mixCol(a, b, t) { return new THREE.Color(a).lerp(new THREE.Color(b), t); }

const store = {
  get(k, d) { try { const v = localStorage.getItem('z3_' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem('z3_' + k, JSON.stringify(v)); } catch (e) { } }
};

const $ = id => document.getElementById(id);
const isTouch = matchMedia('(pointer: coarse)').matches;
