// Bestiariusz: rodzaje zombie, ich statystyki, wygląd i opis przy pierwszym pojawieniu się.
const ZT = {
  walker: {
    name: 'Zombie', hp: 40, speed: 0.55, dmg: 4, gold: 4, cost: 1, gait: 'shamble', r: 0.22,
    look: { skin: 0x8a9a74, shirt: 0x5a5048, pants: 0x3a3a46, hair: 0x2a2018 }
  },
  runner: {
    name: 'Biegacz', hp: 30, speed: 1.0, dmg: 4, gold: 5, cost: 1.3, gait: 'run', r: 0.2, enrage: true,
    look: { skin: 0x9aa07a, shirt: 0x7a2a22, pants: 0x2a2a30, size: 0.95 },
    intro: 'Im bardziej ranny, tym szybciej biegnie.'
  },
  dog: {
    name: 'Zarażony pies', hp: 22, speed: 1.5, dmg: 3, gold: 3, cost: 0.6, gait: 'dog', r: 0.2, pack: 3,
    look: { dog: true, skin: 0x5a4a3c },
    intro: 'Atakują stadami po trzy. Słabe, ale bardzo szybkie.'
  },
  crawler: {
    name: 'Pełzacz', hp: 45, speed: 0.45, dmg: 4, gold: 5, cost: 1.4, gait: 'crawl', r: 0.22, noBlock: true,
    look: { skin: 0x7a8a6a, shirt: 0x4a4038, pants: 0x30302a },
    intro: 'Pełznie pod nogami żołnierzy - posterunki go nie zatrzymają.'
  },
  bloater: {
    name: 'Rozdęty', hp: 110, speed: 0.4, dmg: 8, gold: 8, cost: 2.5, gait: 'shamble', r: 0.32, explode: 1.5,
    look: {
      skin: 0x9aaa6a, shirt: 0x6a6a4a, pants: 0x4a4a3a, w: 1.5, size: 1.15,
      torsoExtra: (t, s) => { t.ball(0.28, shade(0x9aaa6a, 0.95), 0, 0.2, 0.08, 1, 1.1, 1, 1); t.ball(0.07, 0x5dff4a, 0.12, 0.25, 0.32, 0); }
    },
    intro: 'Wybucha przy śmierci i rani wszystkich wokół - żołnierzy i inne zombie.'
  },
  spitter: {
    name: 'Plujący', hp: 50, speed: 0.55, dmg: 5, gold: 7, cost: 2, gait: 'shamble', r: 0.22, spit: true,
    look: { skin: 0x7aaa5a, shirt: 0x3a4a3a, pants: 0x2a3a2a, eye: 0x9aff5a, glowExtra: g => g.box(0.12, 0.05, 0.02, 0x8aff3a, 0, 0.49, 0.14) },
    intro: 'Pluje kwasem w żołnierzy z dystansu.'
  },
  riot: {
    name: 'Opancerzony', hp: 120, speed: 0.45, dmg: 6, gold: 9, cost: 3, gait: 'shamble', r: 0.25, armor: 0.5,
    look: {
      skin: 0x8a9478, shirt: 0x1e2430, pants: 0x1a1e28, shoe: 0x101010,
      torsoExtra: t => { t.box(0.27, 0.15, 0.27, 0x14181f, 0, 0.55, 0.02); t.box(0.2, 0.07, 0.02, 0x7a9aaa, 0, 0.55, 0.15); },
      armExtra: a => { a.box(0.04, 0.42, 0.3, 0x3a4250, 0.06, -0.48, 0.06); }
    },
    intro: 'Kamizelka i tarcza: kule zadają mu o połowę mniej obrażeń. Moździerz i Tesla działają normalnie.'
  },
  screamer: {
    name: 'Krzykacz', hp: 60, speed: 0.6, dmg: 4, gold: 8, cost: 2.5, gait: 'shamble', r: 0.22, aura: 2.2,
    look: { skin: 0xb0b098, shirt: 0xa89a7a, pants: 0x4a4038, hair: 0xd8d0c0, torsoExtra: t => t.box(0.1, 0.07, 0.02, 0x100404, 0, 0.47, 0.14) },
    intro: 'Jego wrzask przyspiesza zombie w pobliżu. Zabij go pierwszego.'
  },
  swarm: {
    name: 'Roj', hp: 70, speed: 0.55, dmg: 5, gold: 6, cost: 2.5, gait: 'shamble', r: 0.25, split: 3,
    look: { skin: 0x6a7a5a, shirt: 0x5a3a4a, pants: 0x3a2a3a, w: 1.2, torsoExtra: t => { for (let i = 0; i < 5; i++) t.ball(0.05, 0x9a3a5a, rr(-0.15, 0.15), rr(0.05, 0.35), 0.12, 0); } },
    intro: 'Po śmierci rozpada się na trzy małe, szybkie zombie.'
  },
  mini: {
    name: 'Mały', hp: 18, speed: 0.95, dmg: 2, gold: 1, cost: 0.5, gait: 'run', r: 0.15,
    look: { skin: 0x7a8a62, shirt: 0x5a3a4a, pants: 0x3a2a3a, size: 0.6 }
  },
  glow: {
    name: 'Radioaktywny', hp: 70, speed: 0.6, dmg: 5, gold: 9, cost: 2.5, gait: 'shamble', r: 0.22, phase: true,
    look: { skin: 0x6aff6a, shirt: 0x2a3a2a, pants: 0x2a2a2a, eye: 0xffffff, glowExtra: g => { g.box(0.18, 0.18, 0.02, 0x7dff5a, 0, 0.12, 0.115); } },
    intro: 'Co kilka sekund staje się nieuchwytny - kule i odłamki przez niego przelatują. Tesla trafia zawsze.'
  },
  brute: {
    name: 'Kolos', hp: 380, speed: 0.35, dmg: 15, gold: 20, cost: 7, gait: 'shamble', r: 0.38, regen: 6,
    look: { skin: 0x7a8a6a, shirt: 0x4a3a30, pants: 0x3a3028, w: 1.5, size: 1.6, hair: 0x1a1410 },
    intro: 'Ogromny i wytrzymały. Leczy rany, jeśli nie zadajesz obrażeń bez przerwy.'
  },
  necro: {
    name: 'Pacjent Zero', hp: 160, speed: 0.45, dmg: 10, gold: 18, cost: 6, gait: 'shamble', r: 0.24, raise: true,
    look: {
      skin: 0xa8b0a0, shirt: 0xdedede, pants: 0x9aa0a8, eye: 0xff3a3a,
      torsoExtra: t => { t.box(0.38, 0.5, 0.23, 0xe8e8e8, 0, -0.08, 0); t.box(0.05, 0.25, 0.02, 0x8a1a1a, 0.08, 0.1, 0.12); },
      glowExtra: g => g.box(0.06, 0.04, 0.02, 0xff3a3a, 0, 0.6, 0.14)
    },
    intro: 'Pierwszy zarażony. Co kilka sekund podnosi z ziemi nowe zombie.'
  },
  // ---- bossowie: jeden na biom ----
  butcher: {
    name: 'RZEŹNIK', hp: 1900, speed: 0.32, dmg: 40, gold: 150, cost: 0, gait: 'shamble', r: 0.55, boss: true, summon: true, noBlock: true, hp2: 1,
    look: {
      skin: 0xa09080, shirt: 0x6a5a4a, pants: 0x3a3028, w: 1.6, size: 2.5,
      torsoExtra: t => { t.box(0.42, 0.42, 0.04, 0xc8c0b0, 0, -0.05, 0.12); t.box(0.2, 0.12, 0.03, 0x6a0d0a, 0.05, 0.1, 0.14); },
      armRExtra: a => { a.box(0.04, 0.08, 0.3, 0x4a3020, 0, -0.5, 0.1); a.box(0.03, 0.2, 0.3, 0xb8c0c8, 0, -0.62, 0.32); }
    },
    intro: 'RZEŹNIK - przy dwóch trzecich i jednej trzeciej życia przyzywa biegaczy. Tasakiem rozbija oddziały.'
  },
  giant: {
    name: 'LODOWY OLBRZYM', hp: 2300, speed: 0.28, dmg: 50, gold: 170, cost: 0, gait: 'shamble', r: 0.6, boss: true, freeze: true, noBlock: true,
    look: {
      skin: 0x9ab8d0, shirt: 0x5a7a9a, pants: 0x3a4a5a, w: 1.5, size: 2.8, eye: 0x9ff0ff,
      torsoExtra: t => { for (let i = 0; i < 5; i++) t.cone(0.06, rr(0.15, 0.3), 0xd8f4ff, rr(-0.15, 0.15), 0.38, rr(-0.1, 0.05), 4); },
      glowExtra: g => g.box(0.15, 0.04, 0.02, 0x9ff0ff, 0, 0.56, 0.14)
    },
    intro: 'LODOWY OLBRZYM - co kilka sekund zamraża wieże w pobliżu.'
  },
  queen: {
    name: 'KRÓLOWA ROJU', hp: 2000, speed: 0.3, dmg: 45, gold: 160, cost: 0, gait: 'shamble', r: 0.6, boss: true, brood: true, noBlock: true,
    look: {
      skin: 0x8a9a5a, shirt: 0x6a3a5a, pants: 0x3a2a3a, w: 1.7, size: 2.4,
      torsoExtra: t => { t.ball(0.32, 0x7a3a5a, 0, 0.15, -0.18, 1, 1, 1.1, 1.2); for (let i = 0; i < 8; i++) t.ball(0.05, 0xc85a8a, rr(-0.25, 0.25), rr(0, 0.35), rr(-0.4, 0.05), 0); },
      glowExtra: g => { for (let i = 0; i < 4; i++) g.ball(0.04, 0xb6ff6a, rr(-0.2, 0.2), rr(0.05, 0.3), -0.42, 0); }
    },
    intro: 'KRÓLOWA ROJU - składa jaja z małymi zombie, a po śmierci wypuszcza cały rój.'
  }
};

// Kolejność odblokowywania rodzajów (fala, od której się pojawiają).
const UNLOCK = [['walker', 1], ['runner', 2], ['dog', 3], ['crawler', 4], ['bloater', 6], ['spitter', 7], ['riot', 8], ['screamer', 9], ['swarm', 11], ['glow', 12], ['brute', 13], ['necro', 14]];
