// Soundtrack for the Sabily brag: music + SFX composed as one piece.
// 120 BPM, D major, bars at 1.0 + 2k s. Every SFX is voiced from the chord
// tones and placed on the composition's own cue times (index.html).
// Deterministic: a seeded PRNG, no clocks. Output: 48 kHz stereo 16-bit WAV.
"use strict";
const fs = require("fs");
const path = require("path");

const SR = 48000;
const DUR = 22.0;
const N = Math.round(SR * DUR);
const OUT = path.join(__dirname, "soundtrack_raw.wav");

// buses
const L = new Float32Array(N), R = new Float32Array(N); // dry
const rvL = new Float32Array(N), rvR = new Float32Array(N); // reverb send
const dlL = new Float32Array(N), dlR = new Float32Array(N); // delay send
const duck = new Float32Array(N).fill(1); // sidechain gain from the kick

let seed = 0x2f6bff;
function rnd() { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 4294967296; }
const noise = () => rnd() * 2 - 1;
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
const idx = (t) => Math.round(t * SR);
const db = (d) => Math.pow(10, d / 20);

function put(i, l, r, send = 0, dsend = 0) {
  if (i < 0 || i >= N) return;
  L[i] += l; R[i] += r;
  if (send) { rvL[i] += l * send; rvR[i] += r * send; }
  if (dsend) { dlL[i] += l * dsend; dlR[i] += r * dsend; }
}
function panLR(p) { const a = ((p + 1) * Math.PI) / 4; return [Math.cos(a), Math.sin(a)]; }

// TPT state-variable filter
class SVF {
  constructor() { this.a = 0; this.b = 0; }
  run(x, fc, q, mode) {
    const g = Math.tan((Math.PI * Math.min(fc, SR * 0.45)) / SR), k = 1 / q;
    const a1 = 1 / (1 + g * (g + k)), a2 = g * a1, a3 = g * a2;
    const v3 = x - this.b, v1 = a1 * this.a + a2 * v3, v2 = this.b + a2 * this.a + a3 * v3;
    this.a = 2 * v1 - this.a; this.b = 2 * v2 - this.b;
    return mode === "lp" ? v2 : mode === "bp" ? v1 : x - k * v1 - v2;
  }
}
function blep(t, dt) {
  if (t < dt) { t /= dt; return t + t - t * t - 1; }
  if (t > 1 - dt) { t = (t - 1) / dt; return t * t + t + t + 1; }
  return 0;
}
class Saw {
  constructor(f, ph) { this.f = f; this.p = ph === undefined ? rnd() : ph; }
  next() { const dt = this.f / SR; let v = 2 * this.p - 1 - blep(this.p, dt); this.p += dt; if (this.p >= 1) this.p -= 1; return v; }
}

// ── drums ────────────────────────────────────────────────────────────────
function kick(t, g = 1) {
  const i0 = idx(t);
  for (let i = i0; i < Math.min(N, i0 + SR * 0.45); i++) { const d = (i - i0) / SR; duck[i] = Math.min(duck[i], 1 - 0.72 * Math.exp(-d / 0.1)); }
  let ph = 0;
  for (let n = 0; n < SR * 0.5; n++) {
    const d = n / SR;
    const f = 53 + 140 * Math.exp(-d / 0.03) + 30 * Math.exp(-d / 0.13);
    ph += (2 * Math.PI * f) / SR;
    let v = Math.sin(ph) * Math.exp(-d / 0.24) * Math.min(1, d / 0.0015);
    if (d < 0.003) v += noise() * 0.45 * (1 - d / 0.003);
    v += Math.sin(2 * Math.PI * 185 * d) * 0.32 * Math.exp(-d / 0.022);
    v = Math.tanh(v * 1.5) / Math.tanh(1.5);
    put(i0 + n, v * g, v * g);
  }
}
function clap(t, g = 1) {
  const i0 = idx(t), f = new SVF(), f2 = new SVF();
  const [pl, pr] = panLR(0.06);
  for (let n = 0; n < SR * 0.4; n++) {
    const d = n / SR;
    let env = 0;
    for (const o of [0, 0.0105, 0.021]) if (d >= o) env += Math.exp(-(d - o) / 0.0055);
    if (d >= 0.027) env += 0.55 * Math.exp(-(d - 0.027) / 0.12);
    const y = f2.run(f.run(noise(), 1700, 1.0, "bp"), 7000, 0.7, "lp");
    const v = (y * 1.6 + noise() * 0.18 * Math.exp(-d / 0.012)) * env * g;
    put(i0 + n, v * pl, v * pr, 0.32);
  }
}
function hat(t, open, g = 1, p = 0.22) {
  const i0 = idx(t), f = new SVF(), f2 = new SVF();
  const [pl, pr] = panLR(p);
  const dec = open ? 0.13 : 0.03;
  for (let n = 0; n < SR * (open ? 0.4 : 0.1); n++) {
    const d = n / SR;
    const y = f2.run(f.run(noise(), 7600, 0.8, "hp"), 12500, 0.7, "lp");
    const v = y * Math.exp(-d / dec) * g;
    put(i0 + n, v * pl, v * pr, open ? 0.12 : 0);
  }
}
function snare(t, g = 1) {
  const i0 = idx(t), f = new SVF();
  let ph = 0;
  for (let n = 0; n < SR * 0.25; n++) {
    const d = n / SR;
    ph += (2 * Math.PI * (190 + 60 * Math.exp(-d / 0.02))) / SR;
    const body = Math.sin(ph) * Math.exp(-d / 0.05) * 0.6;
    const sn = f.run(noise(), 2400, 0.8, "bp") * Math.exp(-d / 0.09) * 1.4;
    const v = (body + sn) * g;
    put(i0 + n, v, v, 0.2);
  }
}
function crash(t, g = 1, len = 2.2) {
  const i0 = idx(t), fl = new SVF(), fr = new SVF(), ll = new SVF(), lr = new SVF();
  for (let n = 0; n < SR * len; n++) {
    const d = n / SR, env = Math.exp(-d / (len * 0.34)) * Math.min(1, d / 0.004);
    const cut = 4000 + 9000 * Math.exp(-d / 0.5);
    const a = ll.run(fl.run(noise(), 3800, 0.7, "hp"), cut, 0.7, "lp");
    const b = lr.run(fr.run(noise(), 3800, 0.7, "hp"), cut, 0.7, "lp");
    put(i0 + n, a * env * g, b * env * g, 0.25);
  }
}

// ── tonal ────────────────────────────────────────────────────────────────
function bass(t, dur, m, g = 1) {
  const i0 = idx(t), f = new SVF(), s = new Saw(midi(m), 0);
  let ph = 0;
  const len = Math.round(dur * SR);
  for (let n = 0; n < len + SR * 0.05; n++) {
    const d = n / SR;
    const env = Math.min(1, d / 0.004) * (n < len ? 0.85 + 0.15 * Math.exp(-d / 0.06) : Math.exp(-(d - dur) / 0.015));
    ph += (2 * Math.PI * midi(m)) / SR;
    const saw = f.run(s.next(), 260 + 1700 * Math.exp(-d / 0.07), 1.1, "lp");
    const i = i0 + n;
    const v = (saw * 0.75 + Math.sin(ph) * 0.55) * env * g * (i < N ? duck[i] : 1);
    put(i, v, v);
  }
}
function pad(t0, t1, notes, g, cut) {
  const i0 = idx(t0), i1 = idx(t1), rel = 0.45;
  const voices = [];
  notes.forEach((m, k) => {
    [-13, -6, 0, 6, 13].forEach((c, j) => {
      voices.push({ o: new Saw(midi(m) * Math.pow(2, c / 1200)), pan: ((j - 2) / 2) * 0.7 * (k % 2 ? -1 : 1) });
    });
  });
  const fl = new SVF(), fr = new SVF();
  for (let i = i0; i < Math.min(N, i1 + SR * rel); i++) {
    const d = (i - i0) / SR;
    const env = Math.min(1, d / 0.09) * (i < i1 ? 1 : Math.exp(-((i - i1) / SR) / (rel / 3)));
    let l = 0, r = 0;
    for (const v of voices) { const x = v.o.next(); const [pl, pr] = panLR(v.pan); l += x * pl; r += x * pr; }
    const c = typeof cut === "function" ? cut(i / SR) : cut;
    const k = (env * g * duck[i]) / voices.length;
    put(i, fl.run(l, c, 0.8, "lp") * k * 2.2, fr.run(r, c, 0.8, "lp") * k * 2.2, 0.38);
  }
}
function pluck(t, m, g, p, bright = 1) {
  const i0 = idx(t), f = new SVF(), a = new Saw(midi(m), 0), b = new Saw(midi(m) * 1.004, 0.3);
  const [pl, pr] = panLR(p);
  for (let n = 0; n < SR * 0.32; n++) {
    const d = n / SR, i = i0 + n;
    const y = f.run((a.next() + b.next()) * 0.5, 600 + 5200 * bright * Math.exp(-d / 0.09), 1.3, "lp");
    const v = y * Math.exp(-d / 0.14) * Math.min(1, d / 0.002) * g * (i < N ? duck[i] : 1);
    put(i, v * pl, v * pr, 0.2, 0.45);
  }
}
function stab(t, notes, g = 1, dec = 0.9) {
  const i0 = idx(t);
  const vs = [];
  notes.forEach((m) => [-11, 0, 11].forEach((c, j) => vs.push({ o: new Saw(midi(m) * Math.pow(2, c / 1200)), p: (j - 1) * 0.6 })));
  const fl = new SVF(), fr = new SVF();
  for (let n = 0; n < SR * (dec * 3); n++) {
    const d = n / SR;
    const env = Math.min(1, d / 0.003) * Math.exp(-d / dec);
    let l = 0, r = 0;
    for (const v of vs) { const x = v.o.next(); const [pl, pr] = panLR(v.p); l += x * pl; r += x * pr; }
    const c = 1800 + 5200 * Math.exp(-d / 0.25);
    const k = (env * g) / vs.length * 2.4;
    put(i0 + n, fl.run(l, c, 0.8, "lp") * k, fr.run(r, c, 0.8, "lp") * k, 0.5);
  }
}
function bell(t, m, g = 1, p = 0, dec = 1) {
  const i0 = idx(t), f0 = midi(m);
  const parts = [[1, 1, 1.1], [2, 0.35, 0.7], [2.76, 0.28, 0.38], [5.4, 0.1, 0.12]];
  const [pl, pr] = panLR(p);
  for (let n = 0; n < SR * 2.2 * dec; n++) {
    const d = n / SR;
    let v = 0;
    for (const [h, a, dcy] of parts) v += Math.sin(2 * Math.PI * f0 * h * d) * a * Math.exp(-d / (dcy * dec));
    v *= Math.min(1, d / 0.0012) * g;
    put(i0 + n, v * pl, v * pr, 0.42);
  }
}
function subBoom(t, g = 1) {
  const i0 = idx(t);
  let ph = 0;
  for (let n = 0; n < SR * 1.6; n++) {
    const d = n / SR;
    ph += (2 * Math.PI * (44 + 30 * Math.exp(-d / 0.35))) / SR;
    const v = Math.sin(ph) * Math.exp(-d / 0.65) * Math.min(1, d / 0.006) * g;
    put(i0 + n, v, v);
  }
}

// ── transitions & UI ─────────────────────────────────────────────────────
function riser(t0, t1, g = 1) {
  const i0 = idx(t0), i1 = idx(t1), fl = new SVF(), fr = new SVF();
  let ph = 0;
  for (let i = i0; i < i1; i++) {
    const u = (i - i0) / (i1 - i0);
    const fc = 300 * Math.pow(7500 / 300, u);
    const env = (0.12 + 0.88 * Math.pow(u, 1.6)) * g;
    ph += (2 * Math.PI * midi(50 + 24 * u)) / SR;
    const tone = Math.sin(ph) * 0.18;
    put(i, (fl.run(noise(), fc, 1.4, "bp") + tone) * env, (fr.run(noise(), fc, 1.4, "bp") + tone) * env, 0.3);
  }
}
function whoosh(tc, g = 1, len = 0.46) {
  const t0 = tc - len * 0.62, i0 = idx(t0), n1 = Math.round(len * SR), fl = new SVF(), fr = new SVF();
  for (let n = 0; n < n1; n++) {
    const u = n / n1;
    const fc = 500 + 3200 * Math.sin(Math.PI * Math.min(1, u * 1.15));
    const env = Math.pow(Math.sin(Math.PI * u), 2) * g;
    put(i0 + n, fl.run(noise(), fc, 0.9, "bp") * env * 1.3, fr.run(noise(), fc * 1.07, 0.9, "bp") * env * 1.3, 0.18);
  }
}
function swoosh(t, g = 1, up = true) {
  const i0 = idx(t), n1 = Math.round(0.26 * SR), f = new SVF();
  for (let n = 0; n < n1; n++) {
    const u = n / n1;
    const fc = up ? 900 + 2600 * u : 3500 - 2600 * u;
    const v = f.run(noise(), fc, 1.2, "bp") * Math.sin(Math.PI * u) * g;
    put(i0 + n, v, v, 0.15);
  }
}
function tapClick(t, g = 1) {
  const i0 = idx(t), f = new SVF();
  for (let n = 0; n < SR * 0.09; n++) {
    const d = n / SR;
    let v = Math.sin(2 * Math.PI * midi(81) * d) * Math.exp(-d / 0.018) * 0.7 + Math.sin(2 * Math.PI * midi(69) * d) * Math.exp(-d / 0.035) * 0.5;
    if (d < 0.004) v += f.run(noise(), 4000, 0.8, "hp") * (1 - d / 0.004) * 0.5;
    put(i0 + n, v * g, v * g, 0.08);
  }
}
function tick(t, m, g = 1, p = 0) {
  const i0 = idx(t), [pl, pr] = panLR(p);
  for (let n = 0; n < SR * 0.06; n++) {
    const d = n / SR;
    const v = (Math.sin(2 * Math.PI * midi(m) * d) + 0.35 * Math.sin(2 * Math.PI * midi(m + 12) * d)) * Math.exp(-d / 0.014) * Math.min(1, d / 0.0008) * g;
    put(i0 + n, v * pl, v * pr, 0.1);
  }
}
function pop(t, m0, m1, g = 1, p = 0) {
  const i0 = idx(t), [pl, pr] = panLR(p);
  let ph = 0;
  for (let n = 0; n < SR * 0.12; n++) {
    const d = n / SR;
    const f = midi(m0 + (m1 - m0) * Math.min(1, d / 0.045));
    ph += (2 * Math.PI * f) / SR;
    const v = Math.sin(ph) * Math.exp(-d / 0.04) * Math.min(1, d / 0.001) * g;
    put(i0 + n, v * pl, v * pr, 0.15);
  }
}

// ── the arrangement ──────────────────────────────────────────────────────
const CH = { D: [62, 66, 69, 74], G: [62, 67, 71, 74], A: [61, 64, 69, 73], Bm: [62, 66, 71, 74], Asus: [62, 64, 69, 74] };
const ROOT = { D: 38, G: 43, A: 45, Bm: 47, Asus: 45 };
const ARP = { D: [62, 66, 69, 74, 78, 81], G: [62, 67, 71, 74, 79, 83], A: [61, 64, 69, 73, 76, 81], Bm: [62, 66, 71, 74, 78, 83] };
const BARS = [
  [1, "D", "hook"], [3, "G", "break"], [5, "D", "main"], [7, "A", "main"], [9, "Bm", "main"],
  [11, "G", "main"], [13, "D", "main"], [15, "Bm", "main"], [17, "G", "outro"], [19, "A", "end"],
];

// kicks first: they write the sidechain curve everything tonal reads
const KG = db(-4.5);
for (const [t0, , sec] of BARS) {
  if (sec === "break") continue;
  for (let b = 0; b < 4; b++) {
    const t = t0 + b * 0.5;
    if (sec === "end" && (b === 1 || b === 3) && t < 20.5) continue;
    kick(t, KG);
  }
}
kick(21.0, KG);

for (const [t0, ch, sec] of BARS) {
  const t1 = t0 + 2;
  const full = sec === "main" || sec === "outro";
  // pad
  const cut = sec === "break" ? (t) => 700 + 4300 * Math.pow((t - t0) / 2, 1.6) : sec === "end" ? 4200 : sec === "outro" ? 6500 : full ? 5500 : 4200;
  pad(t0, t1, sec === "end" ? CH.Asus : CH[ch], db(sec === "break" ? -2 : -4.5), cut);
  // bass on the offbeats (house pump)
  if (sec !== "break") for (let b = 0; b < 4; b++) bass(t0 + b * 0.5 + 0.25, 0.2, ROOT[ch], db(-9.5));
  // clap 2 & 4
  if (sec !== "break" && sec !== "end") { clap(t0 + 0.5, db(-5)); clap(t0 + 1.5, db(-5)); }
  if (sec === "end") clap(t0 + 1.0, db(-7));
  // hats
  if (sec !== "break") {
    for (let b = 0; b < 4; b++) hat(t0 + b * 0.5 + 0.25, true, db(-14), 0.25);
    if (full) for (let s = 0; s < 16; s++) if (s % 2 === 1) hat(t0 + s * 0.125, false, db(s % 4 === 3 ? -19 : -22), -0.2);
  }
  // 16th pluck arp, brighter once the product is on screen
  const notes = ARP[ch];
  const order = [0, 2, 1, 3, 2, 4, 3, 5];
  for (let s = 0; s < 16; s++) {
    const m = notes[order[s % 8]];
    const g = sec === "break" ? db(-13) : sec === "hook" ? db(-14) : db(-11.5);
    pluck(t0 + s * 0.125, m, g, s % 2 ? 0.35 : -0.35, sec === "break" ? 0.45 : full ? 1 : 0.7);
  }
}
// the hook: from frame 0, a pad swell and filtered plucks rising into the first downbeat
pad(0.0, 1.0, CH.D, db(-8), (t) => 450 + 2600 * Math.pow(t / 1.0, 1.5));
for (let s = 0; s < 8; s++) pluck(s * 0.125, ARP.D[[0, 2, 1, 3, 2, 4, 3, 5][s]], db(-22 + s * 0.6), s % 2 ? 0.35 : -0.35, 0.3 + s * 0.06);
riser(0.0, 1.0, db(-12));
// the reveal keeps a soft half-time pulse so the breakdown never reads as a dropout
kick(3.0, db(-10)); kick(4.0, db(-12));
stab(1.0, CH.D, db(-7), 0.7); subBoom(1.0, db(-10)); crash(1.0, db(-15));
// globe pins: a soft pentatonic run, sitting well under the groove
[74, 76, 78, 81, 83, 86, 88, 90].forEach((m, i) => pop(1.0 + i * 0.1, m - 5, m, db(-27), i % 2 ? 0.4 : -0.4));
tick(1.13, 81, db(-22));
whoosh(2.5, db(-15));
// reveal: the sting's plane leaves and lands, the wordmark settles
swoosh(2.78, db(-24), true); swoosh(3.32, db(-25), false); pop(3.56, 74, 81, db(-26));
bell(4.08, 74, db(-18), -0.2); bell(4.11, 81, db(-21), 0.2); subBoom(4.08, db(-16));
riser(4.2, 5.0, db(-13));
for (let s = 0; s < 8; s++) snare(4.5 + s * 0.0625, db(-24 + s * 1.3));
whoosh(5.0, db(-15));
stab(5.0, CH.D, db(-8), 0.6); subBoom(5.0, db(-11)); crash(5.0, db(-15));
// +200 counter: a decelerating roll of ticks
{ let t = 5.14, dt = 0.03; for (let k = 0; k < 16 && t < 5.95; k++) { tick(t, k % 2 ? 86 : 81, db(-29 + k * 0.25), k % 2 ? 0.3 : -0.3); t += dt; dt *= 1.13; } }
tick(6.03, 81, db(-22));
whoosh(8.0, db(-16));
tapClick(8.34, db(-19)); swoosh(8.55, db(-26));
tick(9.09, 81, db(-22));
tapClick(10.36, db(-19)); bell(10.4, 76, db(-22), -0.15); bell(10.47, 81, db(-21), 0.15);
whoosh(11.0, db(-16)); crash(11.0, db(-21), 1.4);
swoosh(11.55, db(-26)); tick(12.13, 81, db(-22));
whoosh(14.0, db(-16));
tapClick(14.78, db(-19)); swoosh(15.05, db(-26)); swoosh(15.32, db(-23), true);
pop(15.5, 74, 81, db(-22));
// connected: the four bars fill, then the bell arpeggio
[69, 74, 78, 81].forEach((m, i) => tick(15.96 + i * 0.05, m + 12, db(-24), i % 2 ? 0.25 : -0.25));
[74, 78, 81, 86].forEach((m, i) => bell(16.0 + i * 0.065, m, db(-15), (i - 1.5) * 0.25));
// into the outro
riser(16.45, 17.0, db(-14));
for (let s = 0; s < 8; s++) snare(16.5 + s * 0.0625, db(-24 + s * 1.2));
whoosh(17.0, db(-15));
stab(17.0, CH.G, db(-7), 0.8); subBoom(17.0, db(-10)); crash(17.0, db(-14));
tick(17.81, 81, db(-22)); pop(17.99, 76, 83, db(-21));
whoosh(19.0, db(-16));
swoosh(19.06, db(-24)); pop(19.12, 69, 76, db(-24));
tapClick(20.02, db(-18)); pop(20.16, 74, 86, db(-19)); bell(20.26, 86, db(-22));
for (let s = 0; s < 8; s++) snare(20.5 + s * 0.0625, db(-25 + s * 1.3));
// resolve to the tonic
stab(21.0, [50, 57, 62, 66, 69, 74], db(-6), 1.1); subBoom(21.0, db(-9)); crash(21.0, db(-13), 2.6);
bell(21.0, 74, db(-17)); bell(21.0, 81, db(-20), 0.3);
pad(21.0, 21.6, CH.D, db(-13), 2800);
bass(21.0, 0.6, 38, db(-6));

// ── effects returns ──────────────────────────────────────────────────────
function freeverb(inp, spread, room, damp) {
  const combT = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617].map((x) => Math.round(((x + spread) * SR) / 44100));
  const apT = [556, 441, 341, 225].map((x) => Math.round(((x + spread) * SR) / 44100));
  const combs = combT.map((t) => ({ b: new Float32Array(t), i: 0, s: 0 }));
  const aps = apT.map((t) => ({ b: new Float32Array(t), i: 0 }));
  const out = new Float32Array(N);
  for (let n = 0; n < N; n++) {
    const x = inp[n] * 0.015;
    let s = 0;
    for (const c of combs) { const y = c.b[c.i]; c.s = y * (1 - damp) + c.s * damp; c.b[c.i] = x + c.s * room; if (++c.i >= c.b.length) c.i = 0; s += y; }
    for (const a of aps) { const bv = a.b[a.i]; const y = -s + bv; a.b[a.i] = s + bv * 0.5; if (++a.i >= a.b.length) a.i = 0; s = y; }
    out[n] = s;
  }
  return out;
}
const wetL = freeverb(rvL, 0, 0.86, 0.32), wetR = freeverb(rvR, 23, 0.86, 0.32);
// dotted-eighth ping-pong for the plucks
const DT = Math.round(0.375 * SR), fbL = new SVF(), fbR = new SVF();
const dOutL = new Float32Array(N), dOutR = new Float32Array(N);
for (let n = 0; n < N; n++) {
  const pl = n >= DT ? dOutR[n - DT] : 0, pr = n >= DT ? dOutL[n - DT] : 0;
  dOutL[n] = dlL[n] + fbL.run(pl, 3200, 0.7, "lp") * 0.38;
  dOutR[n] = dlR[n] * 0.2 + fbR.run(pr, 3200, 0.7, "lp") * 0.38;
}

// ── master ───────────────────────────────────────────────────────────────
const hpL = new SVF(), hpR = new SVF(), shL = new SVF(), shR = new SVF();
const SHELF = db(3) - 1;
const mL = new Float32Array(N), mR = new Float32Array(N);
const WET = db(-3.5), DLY = db(-12);
let peak = 0;
for (let n = 0; n < N; n++) {
  const t = n / SR;
  let l = L[n] + wetL[n] * WET + dOutL[n] * DLY;
  let r = R[n] + wetR[n] * WET + dOutR[n] * DLY;
  l = hpL.run(l, 28, 0.7, "hp"); r = hpR.run(r, 28, 0.7, "hp");
  l += shL.run(l, 2600, 0.6, "hp") * SHELF; r += shR.run(r, 2600, 0.6, "hp") * SHELF;
  const fade = t > 21.55 ? Math.max(0, 1 - (t - 21.55) / 0.45) : 1;
  mL[n] = l * fade; mR[n] = r * fade;
  peak = Math.max(peak, Math.abs(mL[n]), Math.abs(mR[n]));
}
// gain into a gentle soft-clip, then peak-normalise to -1 dBFS
const knee = (x) => { const a = Math.abs(x); return a < 0.7 ? x : Math.sign(x) * (0.7 + 0.3 * Math.tanh((a - 0.7) / 0.3)); };
let peak2 = 0;
for (let n = 0; n < N; n++) {
  mL[n] = knee(mL[n] / peak); mR[n] = knee(mR[n] / peak);
  peak2 = Math.max(peak2, Math.abs(mL[n]), Math.abs(mR[n]));
}
const norm = db(-3) / peak2;
const buf = Buffer.alloc(44 + N * 4);
buf.write("RIFF", 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write("WAVE", 8);
buf.write("fmt ", 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write("data", 36); buf.writeUInt32LE(N * 4, 40);
for (let n = 0; n < N; n++) {
  buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mL[n] * norm)) * 32767), 44 + n * 4);
  buf.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mR[n] * norm)) * 32767), 46 + n * 4);
}
fs.writeFileSync(OUT, buf);
console.log("wrote", OUT, "raw peak", peak.toFixed(3));
