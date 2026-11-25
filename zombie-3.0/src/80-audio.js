// Dźwięk generowany w kodzie (WebAudio): strzały, wybuchy, wyładowania, zombie, róg fali, wiatr.
const AUDIO = { ctx: null, master: null, muted: store.get('muted', false), noise: null, last: {}, amb: null };

function unlockAudio() {
  if (AUDIO.ctx) { if (AUDIO.ctx.state === 'suspended') AUDIO.ctx.resume(); return; }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  const c = AUDIO.ctx = new AC();
  AUDIO.master = c.createGain(); AUDIO.master.gain.value = AUDIO.muted ? 0 : 0.55;
  const comp = c.createDynamicsCompressor();
  AUDIO.master.connect(comp); comp.connect(c.destination);
  const len = c.sampleRate * 2, buf = c.createBuffer(1, len, c.sampleRate), d = buf.getChannelData(0);
  for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
  AUDIO.noise = buf;
  // wiatr w tle
  const src = c.createBufferSource(); src.buffer = buf; src.loop = true;
  const f = c.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 380;
  const g = c.createGain(); g.gain.value = 0.05;
  src.connect(f); f.connect(g); g.connect(AUDIO.master); src.start();
  AUDIO.amb = { f, g };
}
function setMute(m) { AUDIO.muted = m; store.set('muted', m); if (AUDIO.master) AUDIO.master.gain.value = m ? 0 : 0.55; }
document.addEventListener('visibilitychange', () => { if (AUDIO.ctx) { if (document.hidden) AUDIO.ctx.suspend(); else AUDIO.ctx.resume(); } });

function nz(t, dur, freq, type, vol, q = 1, sweep = 0) {
  const c = AUDIO.ctx, s = c.createBufferSource(); s.buffer = AUDIO.noise;
  s.playbackRate.value = rr(0.8, 1.2);
  const f = c.createBiquadFilter(); f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
  if (sweep) f.frequency.exponentialRampToValueAtTime(Math.max(30, freq * sweep), t + dur);
  const g = c.createGain(); g.gain.setValueAtTime(vol, t); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  s.connect(f); f.connect(g); g.connect(AUDIO.master);
  s.start(t, rr(0, 1)); s.stop(t + dur + 0.05);
}
function tone(t, dur, f0, f1, type, vol, attack = 0.005) {
  const c = AUDIO.ctx, o = c.createOscillator(); o.type = type;
  o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
  const g = c.createGain(); g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + attack); g.gain.exponentialRampToValueAtTime(0.001, t + dur);
  o.connect(g); g.connect(AUDIO.master); o.start(t); o.stop(t + dur + 0.05);
}

const SFX_GAP = { mg: 0.05, rifle: 0.07, die: 0.08, zap: 0.08, spit: 0.15, raise: 0.3, phase: 0.3, hit: 0.15, boom: 0.06, scream: 0.4, build: 0.1, click: 0.05 };
function sfx(name) {
  const c = AUDIO.ctx;
  if (!c || AUDIO.muted || c.state !== 'running') return;
  const t = c.currentTime;
  if (t - (AUDIO.last[name] || 0) < (SFX_GAP[name] || 0.03)) return;
  AUDIO.last[name] = t;
  switch (name) {
    case 'mg': nz(t, 0.07, 2200, 'bandpass', 0.22, 0.8); tone(t, 0.05, 180, 60, 'square', 0.05); break;
    case 'rifle': nz(t, 0.1, 1600, 'bandpass', 0.18, 0.7); break;
    case 'mortar': tone(t, 0.25, 120, 40, 'sine', 0.5); nz(t, 0.2, 600, 'lowpass', 0.25); break;
    case 'boom': nz(t, 0.9, 900, 'lowpass', 0.6, 0.7, 0.08); tone(t, 0.6, 80, 30, 'sine', 0.6); break;
    case 'zap': tone(t, 0.18, 1400, 300, 'sawtooth', 0.09); nz(t, 0.15, 5000, 'highpass', 0.12); tone(t + 0.04, 0.12, 900, 2400, 'square', 0.04); break;
    case 'build': for (let i = 0; i < 3; i++) nz(t + i * 0.12, 0.05, 900 + i * 200, 'bandpass', 0.3, 4); break;
    case 'built': tone(t, 0.2, 520, 520, 'triangle', 0.12); tone(t + 0.09, 0.3, 780, 780, 'triangle', 0.1); break;
    case 'sell': for (let i = 0; i < 4; i++) tone(t + i * 0.05, 0.1, 1800 + i * 300, 1600, 'triangle', 0.06); break;
    case 'click': tone(t, 0.04, 900, 700, 'triangle', 0.06); break;
    case 'nope': tone(t, 0.15, 200, 140, 'square', 0.06); break;
    case 'die': tone(t, rr(0.3, 0.5), rr(140, 200), rr(50, 70), 'sawtooth', 0.06, 0.03); nz(t, 0.2, 500, 'lowpass', 0.1); break;
    case 'bossdie': tone(t, 1.6, 120, 25, 'sawtooth', 0.25, 0.05); nz(t, 1.5, 700, 'lowpass', 0.5, 1, 0.1); break;
    case 'roar': tone(t, 1.3, 70, 45, 'sawtooth', 0.3, 0.2); tone(t, 1.3, 105, 60, 'square', 0.1, 0.2); nz(t, 1.2, 400, 'bandpass', 0.25, 1.5); break;
    case 'horn': tone(t, 1.1, 146, 146, 'sawtooth', 0.12, 0.15); tone(t + 0.6, 1.0, 196, 196, 'sawtooth', 0.1, 0.1); break;
    case 'horn2': tone(t, 1.6, 98, 92, 'sawtooth', 0.16, 0.2); tone(t, 1.6, 147, 139, 'sawtooth', 0.1, 0.2); break;
    case 'hit': tone(t, 0.4, 90, 40, 'sine', 0.5); nz(t, 0.3, 800, 'lowpass', 0.3); break;
    case 'scream': tone(t, 0.3, 700, 300, 'sawtooth', 0.05, 0.02); break;
    case 'spit': nz(t, 0.18, 1200, 'bandpass', 0.15, 3, 0.4); break;
    case 'phase': tone(t, 0.4, 300, 1200, 'sine', 0.05, 0.1); break;
    case 'raise': tone(t, 0.6, 60, 120, 'sawtooth', 0.08, 0.3); nz(t, 0.5, 300, 'lowpass', 0.15); break;
    case 'freeze': for (let i = 0; i < 5; i++) tone(t + i * 0.04, 0.5, 2400 + i * 400, 3000, 'sine', 0.04); nz(t, 0.6, 6000, 'highpass', 0.15); break;
    case 'smash': tone(t, 0.3, 100, 40, 'square', 0.25); nz(t, 0.3, 1200, 'lowpass', 0.3); break;
    case 'rumble': nz(t, 2.8, 160, 'lowpass', 0.5, 1); tone(t, 2.5, 45, 30, 'sine', 0.3, 0.4); break;
  }
}
// sporadyczne jęki zombie w tle, zależne od liczby żywych
let groanT = 2;
function updateAudio(dt) {
  if (!AUDIO.ctx || AUDIO.muted) return;
  const n = Z.list.filter(e => !e.dead).length;
  groanT -= dt * (0.3 + Math.min(n, 30) * 0.08);
  if (groanT <= 0 && n > 0) {
    groanT = rr(1.5, 3.5);
    const t = AUDIO.ctx.currentTime, f = rr(90, 160);
    tone(t, rr(0.8, 1.4), f, f * rr(0.6, 0.8), 'sawtooth', 0.035, 0.25);
  }
}
