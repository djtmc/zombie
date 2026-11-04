// =====================================================================
//  DŹWIĘK - w całości syntezowany przez WebAudio (zero plików audio)
// =====================================================================

export class Audio {
  constructor() {
    this.ctx = null;
    this.volume = 0.7;
    this.muted = false;
    this.last = {};
    this.listenerX = 0;
  }

  /** AudioContext można utworzyć dopiero po geście użytkownika */
  unlock() {
    if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = this.muted ? 0 : this.volume;
    const comp = this.ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 4;
    this.master.connect(comp).connect(this.ctx.destination);
    // bufor białego szumu
    const len = this.ctx.sampleRate * 2;
    this.noise = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = this.noise.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
    this._ambient();
  }

  setVolume(v) { this.volume = v; this._apply(); }
  setMuted(m) { this.muted = m; this._apply(); }
  _apply() { if (this.master) this.master.gain.setTargetAtTime(this.muted ? 0 : this.volume, this.ctx.currentTime, 0.05); }

  /** Ogranicza liczbę dźwięków tego samego typu na sekundę */
  _gate(key, minGap) {
    if (!this.ctx || this.muted) return false;
    const t = this.ctx.currentTime;
    if (this.last[key] && t - this.last[key] < minGap) return false;
    this.last[key] = t;
    return true;
  }

  /** Panorama i głośność zależne od pozycji na mapie względem kamery */
  _spatial(x) {
    const dx = x === undefined ? 0 : x - this.listenerX;
    const pan = this.ctx.createStereoPanner ? this.ctx.createStereoPanner() : null;
    const g = this.ctx.createGain();
    g.gain.value = x === undefined ? 1 : Math.max(0.15, 1 - Math.abs(dx) / 80);
    if (pan) { pan.pan.value = Math.max(-1, Math.min(1, dx / 45)); g.connect(pan).connect(this.master); }
    else g.connect(this.master);
    return g;
  }

  _noise(dest, t, dur, type, freq, q = 1, gain = 1, freqEnd) {
    const src = this.ctx.createBufferSource();
    src.buffer = this.noise;
    src.playbackRate.value = 0.8 + Math.random() * 0.4;
    const f = this.ctx.createBiquadFilter();
    f.type = type; f.frequency.setValueAtTime(freq, t); f.Q.value = q;
    if (freqEnd) f.frequency.exponentialRampToValueAtTime(freqEnd, t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(gain, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f).connect(g).connect(dest);
    src.start(t, Math.random() * 1.5, dur + 0.05);
  }

  _tone(dest, t, dur, type, f0, f1, gain = 0.3, attack = 0.005) {
    const o = this.ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, t);
    if (f1) o.frequency.exponentialRampToValueAtTime(f1, t + dur);
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(gain, t + attack);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g).connect(dest);
    o.start(t); o.stop(t + dur + 0.05);
  }

  // ---------------------------------------------------------- EFEKTY
  shot(x) {
    if (!this._gate('shot', 0.045)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._noise(d, t, 0.09, 'bandpass', 2200, 0.8, 0.35);
    this._tone(d, t, 0.06, 'square', 320, 90, 0.08);
  }
  cannon(x) {
    if (!this._gate('cannon', 0.08)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._tone(d, t, 0.35, 'sine', 140, 40, 0.7);
    this._noise(d, t, 0.3, 'lowpass', 1400, 0.7, 0.5, 200);
  }
  explosion(x, big) {
    if (!this._gate('boom', 0.06)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._noise(d, t, big ? 1.4 : 0.8, 'lowpass', big ? 900 : 1600, 0.6, big ? 1 : 0.7, 60);
    this._tone(d, t, big ? 0.7 : 0.45, 'sine', 90, 30, big ? 0.9 : 0.6);
  }
  groan(x, boss) {
    if (!this._gate(boss ? 'roar' : 'groan', boss ? 0.5 : 0.7)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    const o = this.ctx.createOscillator();
    o.type = 'sawtooth';
    const base = boss ? 55 : 95 + Math.random() * 50;
    o.frequency.setValueAtTime(base, t);
    o.frequency.linearRampToValueAtTime(base * 0.75, t + 0.9);
    const lfo = this.ctx.createOscillator(); lfo.frequency.value = 6 + Math.random() * 4;
    const lg = this.ctx.createGain(); lg.gain.value = base * 0.06;
    lfo.connect(lg).connect(o.frequency);
    const f = this.ctx.createBiquadFilter(); f.type = 'bandpass'; f.frequency.value = boss ? 400 : 700; f.Q.value = 2;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(boss ? 0.5 : 0.12, t + 0.15);
    g.gain.exponentialRampToValueAtTime(0.001, t + (boss ? 1.6 : 0.9));
    o.connect(f).connect(g).connect(d);
    o.start(t); lfo.start(t); o.stop(t + 1.7); lfo.stop(t + 1.7);
    if (boss) this._noise(d, t, 1.4, 'lowpass', 500, 1, 0.4);
  }
  hit(x) {
    if (!this._gate('hit', 0.05)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._noise(d, t, 0.08, 'lowpass', 700, 1, 0.25);
  }
  splat(x) {
    if (!this._gate('splat', 0.06)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._noise(d, t, 0.25, 'lowpass', 900, 3, 0.4, 150);
  }
  build() {
    if (!this._gate('build', 0.05)) return;
    const t = this.ctx.currentTime, d = this.master;
    for (let i = 0; i < 3; i++) {
      this._noise(d, t + i * 0.09, 0.06, 'bandpass', 1800, 2, 0.5);
      this._tone(d, t + i * 0.09, 0.05, 'triangle', 600, 300, 0.12);
    }
  }
  crumble(x) {
    if (!this._gate('crumble', 0.1)) return;
    const t = this.ctx.currentTime, d = this._spatial(x);
    this._noise(d, t, 0.7, 'lowpass', 1200, 0.5, 0.7, 100);
  }
  coin() {
    if (!this._gate('coin', 0.04)) return;
    const t = this.ctx.currentTime;
    this._tone(this.master, t, 0.08, 'square', 1320, null, 0.05);
    this._tone(this.master, t + 0.06, 0.15, 'square', 1760, null, 0.05);
  }
  click() {
    if (!this._gate('click', 0.03)) return;
    this._tone(this.master, this.ctx.currentTime, 0.05, 'triangle', 900, 700, 0.12);
  }
  error() {
    if (!this._gate('err', 0.15)) return;
    const t = this.ctx.currentTime;
    this._tone(this.master, t, 0.12, 'square', 220, 180, 0.1);
    this._tone(this.master, t + 0.12, 0.16, 'square', 165, 140, 0.1);
  }
  horn() {
    if (!this._gate('horn', 1)) return;
    const t = this.ctx.currentTime;
    for (const [f, dt] of [[110, 0], [138, 0.02], [165, 0.04]]) this._tone(this.master, t + dt, 1.4, 'sawtooth', f, f * 0.98, 0.09, 0.25);
  }
  fanfare() {
    if (!this._gate('fanfare', 1)) return;
    const t = this.ctx.currentTime;
    [523, 659, 784, 1046].forEach((f, i) => this._tone(this.master, t + i * 0.13, 0.4, 'triangle', f, null, 0.22));
  }
  gameOver() {
    const t = this.ctx?.currentTime; if (t === undefined) return;
    [392, 330, 262, 196].forEach((f, i) => this._tone(this.master, t + i * 0.3, 0.6, 'sawtooth', f, f * 0.97, 0.12));
  }
  baseHit() {
    if (!this._gate('basehit', 0.35)) return;
    const t = this.ctx.currentTime;
    this._tone(this.master, t, 0.25, 'sine', 70, 50, 0.4);
  }

  // ---------------------------------------------------------- TŁO
  _ambient() {
    const ctx = this.ctx;
    const src = ctx.createBufferSource();
    src.buffer = this.noise; src.loop = true;
    const f = ctx.createBiquadFilter(); f.type = 'lowpass'; f.frequency.value = 420;
    const g = ctx.createGain(); g.gain.value = 0.05;
    const lfo = ctx.createOscillator(); lfo.frequency.value = 0.08;
    const lg = ctx.createGain(); lg.gain.value = 220;
    lfo.connect(lg).connect(f.frequency);
    src.connect(f).connect(g).connect(this.master);
    src.start(); lfo.start();
    // niski, niepokojący dron
    const o = ctx.createOscillator(); o.type = 'sine'; o.frequency.value = 49;
    const o2 = ctx.createOscillator(); o2.type = 'sine'; o2.frequency.value = 49.6;
    const og = ctx.createGain(); og.gain.value = 0.035;
    o.connect(og); o2.connect(og); og.connect(this.master);
    o.start(); o2.start();
  }
}
