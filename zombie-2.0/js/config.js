// =====================================================================
//  KONFIGURACJA I BALANS GRY
//  Wszystkie wartości czasowe są w SEKUNDACH, prędkości w jednostkach/s.
//  (Wersja 1 liczyła "na klatkę" przy 60 FPS - tu przeliczone x60.)
// =====================================================================

export const MAP = {
  width: 140,
  depth: 72,
};
MAP.baseX = MAP.width / 2 - 8;
MAP.baseZ = 0;
MAP.spawnX = -MAP.width / 2 + 6;
MAP.halfW = MAP.width / 2;
MAP.halfD = MAP.depth / 2;

export const DIFFICULTY = [
  { id: 'easy',   name: 'Łatwa',          scale: 0.60, waveTime: 60, speedMult: 0.65 },
  { id: 'normal', name: 'Średnia',        scale: 0.85, waveTime: 40, speedMult: 0.85 },
  { id: 'hard',   name: 'Ogień w szopie', scale: 1.00, waveTime: 20, speedMult: 1.20 },
];
export const DIFFICULTY_PER_LEVEL = 0.15;

// Przyrost prędkości zombie na poziom maleje wraz z postępem gry
const SPEED_BRACKETS = [
  { max: 10, inc: 0.01 }, { max: 20, inc: 0.005 }, { max: 30, inc: 0.004 },
  { max: 40, inc: 0.003 }, { max: 50, inc: 0.002 }, { max: Infinity, inc: 0.001 },
];
export function levelSpeedBonus(level) {
  let bonus = 0, prev = 0;
  for (const b of SPEED_BRACKETS) {
    if (level <= prev) break;
    bonus += (Math.min(level, b.max) - prev) * b.inc;
    prev = b.max;
  }
  return bonus * 60; // na sekundę
}
export const BOSS_SPEED_RATIO = 0.6;

// Typy zombie (nowe w 2.0). hp/speed/dmg to mnożniki bazowych statystyk.
export const ZOMBIE_TYPES = {
  walker: { name: 'Szwendacz', hp: 1.0, speed: 1.0,  dmg: 1.0, scale: 1.0,  minLevel: 1, weight: 10,
            skins: [0x7fae6a, 0x8fb37a, 0x6d9a5c, 0x9aa98a], cloth: [0x5a4a3a, 0x3e4a5c, 0x6b5b4b, 0x4a3b4f] },
  runner: { name: 'Biegacz',   hp: 0.6, speed: 1.75, dmg: 0.7, scale: 0.9,  minLevel: 3, weight: 4,
            skins: [0xb8c4a0, 0xa9b896], cloth: [0x8a2f2f, 0x2f5a8a] },
  brute:  { name: 'Osiłek',    hp: 3.2, speed: 0.62, dmg: 2.0, scale: 1.4,  minLevel: 5, weight: 2,
            skins: [0x5f7f56, 0x6a7a4a], cloth: [0x2b2b2b, 0x3a2a20] },
};

export const ZOMBIE_BASE = {
  hp: (level) => 50 + level * 20,
  dmg: (level) => 8 + level * 3,       // obrażenia "nominalne" (DPS = dmg * 1.08)
  speed: 2.4,                           // 0.04/klatkę * 60
  dpsFactor: 1.08,                      // 0.018/klatkę * 60
};

// ---------------------------------------------------------------------
//  BUDYNKI
// ---------------------------------------------------------------------
export const BUILDINGS = {
  wall: {
    name: 'Zasieki', icon: '✖️', cost: { wood: 10 }, hp: 100, size: 2, key: '1',
    desc: 'Tani wabik - zombie atakują najbliższy cel.',
  },
  bigwall: {
    name: 'Mur', icon: '🧱', cost: { wood: 25 }, hp: 250, size: 3, key: '2',
    desc: 'Wytrzymała kamienna ściana.',
  },
  cannon: {
    name: 'Armata', icon: '💥', cost: { wood: 30, gold: 25 }, hp: 70, size: 2, key: '3',
    range: 22, damage: 60, fireRate: 1.33, splash: 2.6, shell: 'cannon',
    desc: 'Pociski odłamkowe z obrażeniami obszarowymi.',
    upgrades: 'cannon',
  },
  soldier: {
    name: 'Żołnierz', icon: '🪖', cost: { wood: 100, gold: 150 }, unit: true, size: 1, key: '4',
    desc: 'Mobilny strzelec - sam szuka zombie.',
  },
  koszary: {
    name: 'Koszary', icon: '🏰', cost: { wood: 500, gold: 500 }, hp: 200, size: 3, key: '5',
    produce: 'soldier', interval: 30, limit: 1,
    desc: 'Co 30 s wysyła żołnierzy. Limit: 1.',
    upgrades: 'barracks',
  },
  factory: {
    name: 'Fabryka', icon: '⚙️', cost: { wood: 1000, gold: 1000 }, hp: 120, size: 3, key: '6',
    produce: 'tank', interval: 60,
    desc: 'Co 60 s produkuje czołg.',
  },
  sawmill: {
    name: 'Tartak', icon: '🪚', cost: { wood: 25, gold: 20 }, hp: 60, size: 2, key: '7',
    woodPerSecond: 2, desc: '+2 🪵 na sekundę.', upgrades: 'resource', resource: true,
  },
  mine: {
    name: 'Kopalnia', icon: '⛏️', cost: { wood: 25, gold: 20 }, hp: 60, size: 2, key: '8',
    goldPerSecond: 3, desc: '+3 💰 na sekundę.', upgrades: 'resource', resource: true,
  },
  wielkaArmata: {
    name: 'Wielka Armata', icon: '🎯', cost: { wood: 2000, gold: 2000 }, hp: 200, size: 3, key: '9',
    range: 35, damage: 200, fireRate: 0.83, splash: 4.5, shell: 'big', slotOnly: true, limit: 4,
    desc: 'Stawiana na kamiennych platformach (max 4).',
  },
};
export const BUILD_ORDER = ['wall', 'bigwall', 'cannon', 'soldier', 'koszary', 'factory', 'sawmill', 'mine', 'wielkaArmata'];

export const UNITS = {
  soldier: { hp: 120, range: 18, damage: 40, fireRate: 0.5, speed: 3.0, sight: 25 },
  tank:    { hp: 360, range: 18, damage: 120, fireRate: 0.5, speed: 2.1, sight: 25, splash: 2.0 },
};

export const UPGRADES = {
  cannon: [
    { mult: 3,  desc: 'Podwójny pocisk' },
    { mult: 6,  desc: '+20% obrażeń' },
    { mult: 12, desc: '+20% szybkostrzelności' },
  ],
  resource: [
    { mult: 3,  desc: '+10% produkcji' },
    { mult: 6,  desc: '+20% produkcji' },
    { mult: 12, desc: '+30% produkcji' },
  ],
  barracks: [
    { cost: { wood: 300, gold: 300 },   desc: 'Produkcja żołnierzy x2' },
    { cost: { wood: 900, gold: 900 },   desc: 'Produkcja żołnierzy x4' },
    { cost: { wood: 2000, gold: 2000 }, desc: 'Produkcja żołnierzy x8' },
  ],
};
export const RESOURCE_BONUS = [0, 0.10, 0.20, 0.30];
export const BARRACKS_MULT = [1, 2, 4, 8];

export function upgradeCost(type, tierIndex) {
  const def = BUILDINGS[type];
  const tier = UPGRADES[def.upgrades][tierIndex];
  if (tier.cost) return { wood: tier.cost.wood, gold: tier.cost.gold };
  return { wood: Math.round((def.cost.wood || 0) * tier.mult), gold: Math.round((def.cost.gold || 0) * tier.mult) };
}

export const ARMATA_SLOTS = [
  { x: MAP.halfW - MAP.width * 0.25, z: -MAP.halfD + 4 },
  { x: MAP.halfW - MAP.width * 0.25, z: MAP.halfD - 4 },
  { x: 0, z: -MAP.halfD + 4 },
  { x: 0, z: MAP.halfD - 4 },
];

export const START = { gold: 150, wood: 100, baseHP: 100 };
export const EXCHANGE = { goldToWood: { give: 20, get: 10 }, woodToGold: { give: 10, get: 20 } };
export const SELL_REFUND = 0.5;
export const EARLY_WAVE_BONUS = 15; // złoto za wezwanie fali wcześniej

export const QUALITY = {
  low:    { name: 'Niska',   pixelRatio: 1,   shadows: false, shadowMap: 0,    bloom: false, msaa: 0, grass: 0,    trees: 60,  particles: 0.4 },
  medium: { name: 'Średnia', pixelRatio: 1.5, shadows: true,  shadowMap: 1024, bloom: true,  msaa: 0, grass: 1800, trees: 140, particles: 0.7 },
  high:   { name: 'Wysoka',  pixelRatio: 2,   shadows: true,  shadowMap: 2048, bloom: true,  msaa: 4, grass: 4200, trees: 220, particles: 1.0 },
};

export const BRIGHTNESS = [
  { name: 'Ciemna',  exposure: 0.95 },
  { name: 'Normalna', exposure: 1.25 },
  { name: 'Jasna',   exposure: 1.6 },
];

export const LIMITS = { zombies: 180, units: 140, tanks: 40 };
