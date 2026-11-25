// Kamera: patrzy z południa pod kątem, więc prostokątna plansza wygląda jak prostokątna makieta.
const ZC = STRIP / 2; // środek całej makiety (pole walki + zaplecze)
const CAM = { yaw: 0, tx: 0, tz: 0.6 + ZC, dist: 40, fitDist: 40, pitch: 0.95, follow: true, fit: true, shake: 0, vx: 0, vz: 0, minDist: 9 };

function computeFit() {
  const t = Math.tan(G.camera.fov * Math.PI / 360), a = G.camera.aspect;
  // w pionie (telefon) kamera patrzy z boku, więc długi bok planszy biegnie wzdłuż ekranu
  CAM.yaw = a < 0.9 ? Math.PI / 2 : 0;
  const across = CAM.yaw ? MDT : MW, deep = CAM.yaw ? MW : MDT;
  const needW = (across + 0.4) * 1.1 / (2 * t * a);
  const needH = ((deep + 0.8) * Math.sin(CAM.pitch) + 2.2 * Math.cos(CAM.pitch)) / (2 * t);
  CAM.fitDist = Math.max(needW, needH) * 1.0;
}

function camGround(x, y) {
  const v = new THREE.Vector3((x / G.W) * 2 - 1, -(y / G.H) * 2 + 1, 0.5).unproject(G.camera);
  const o = G.camera.position, d = v.sub(o).normalize();
  if (Math.abs(d.y) < 1e-4) return null;
  const t = -o.y / d.y;
  return t > 0 ? { x: o.x + d.x * t, z: o.z + d.z * t } : null;
}

function zoomAt(f, sx, sy) {
  const before = sx === undefined ? null : camGround(sx, sy);
  CAM.dist = clamp(CAM.dist * f, CAM.minDist, CAM.fitDist * 1.12);
  CAM.fit = false;
  if (before) {
    placeCamera(0);
    const after = camGround(sx, sy);
    if (after) { CAM.tx += before.x - after.x; CAM.tz += before.z - after.z; CAM.follow = false; }
  }
  clampCam();
}
function panBy(dx, dz) { CAM.tx += dx; CAM.tz += dz; CAM.follow = false; clampCam(); }
function clampCam() {
  const k = 1 - Math.min(1, (CAM.dist - CAM.minDist) / Math.max(1, CAM.fitDist - CAM.minDist));
  CAM.tx = clamp(CAM.tx, -MW / 2 * k - 1, MW / 2 * k + 1);
  CAM.tz = clamp(CAM.tz, ZC - MDT / 2 * k - 0.5, ZC + MDT / 2 * k + 1.5);
  if (CAM.yaw) CAM.tx = clamp(CAM.tx, -MW / 2 * k - 0.5, MW / 2 * k + 1.5);
}
function followFight() { CAM.follow = true; CAM.fit = true; }
function shake(a) { CAM.shake = Math.max(CAM.shake, a); }

function placeCamera(dt) {
  if (CAM.fit) CAM.dist = lerp(CAM.dist, CAM.fitDist, Math.min(1, dt * 3));
  if (CAM.follow && dt > 0) {
    let tx = CAM.yaw ? 0.6 : 0, tz = CAM.yaw ? ZC : ZC + 0.6;
    if (CAM.dist < CAM.fitDist * 0.85) {
      // śledź czoło hordy
      const lead = Z.list.filter(e => !e.dead).sort((a, b) => b.s - a.s).slice(0, 4);
      if (lead.length) { tx = lead.reduce((a, e) => a + e.x, 0) / lead.length; tz = lead.reduce((a, e) => a + e.z, 0) / lead.length; }
    }
    CAM.tx = lerp(CAM.tx, tx, Math.min(1, dt * 1.5));
    CAM.tz = lerp(CAM.tz, tz, Math.min(1, dt * 1.5));
    clampCam();
  }
  CAM.shake = Math.max(0, CAM.shake - dt * 1.6);
  const s = CAM.shake * CAM.shake * 0.6;
  const sp = Math.sin(CAM.pitch), cp = Math.cos(CAM.pitch);
  G.camera.position.set(CAM.tx + Math.sin(CAM.yaw) * CAM.dist * cp + rr(-s, s), CAM.dist * sp, CAM.tz + Math.cos(CAM.yaw) * CAM.dist * cp + rr(-s, s));
  G.camera.lookAt(CAM.tx, 0, CAM.tz);
  G.camera.far = CAM.dist * 2 + 40;
  G.camera.updateProjectionMatrix();
  // mgła i ostrość tilt-shift zależne od przybliżenia
  if (G.scene.fog && MAP.biome) { G.scene.fog.near = CAM.dist + 6 + (MAP.biome.fogNear - 30) * 0.3; G.scene.fog.far = CAM.dist + 30 + (MAP.biome.fogFar - 70) * 0.5; }
  const z = CAM.dist / CAM.fitDist;
  POST.mat.uniforms.uBand.value = lerp(0.06, 0.16, clamp(z, 0, 1));
  POST.mat.uniforms.uBlur.value = QUALITY.lv().blur ? lerp(4, 2.0, clamp(z, 0, 1)) : 0;
}
