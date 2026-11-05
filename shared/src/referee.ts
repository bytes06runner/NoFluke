// Luck referee v3 in TypeScript: a checker that must match engine/nofluke/referee.py and Referee.sol bit for bit.
export const WAD = 10n ** 18n;

const MOD = 1n << 256n;
const SIGN = 1n << 255n;
const abs = (x: bigint) => (x < 0n ? -x : x);
const clip = (x: bigint, lo: bigint, hi: bigint) => (x < lo ? lo : x > hi ? hi : x);
const signed = (x: bigint) => {
  const m = ((x % MOD) + MOD) % MOD;
  return m >= SIGN ? m - MOD : m;
};
const sar = (n: bigint, x: bigint) => signed(x) >> n;

function isqrt(n: bigint): bigint {
  if (n < 2n) return n;
  let x = n;
  let y = (x + 1n) >> 1n;
  while (y < x) {
    x = y;
    y = (x + n / x) >> 1n;
  }
  return x;
}

// A port of Solady FixedPointMathLib.lnWad, with EVM word wrapping, so results match exactly.
export function lnWad(input: bigint): bigint {
  if (input <= 0n) throw new Error("lnWad undefined");
  let x = input;
  let r = x > 0xffffffffffffffffffffffffffffffffn ? 128n : 0n;
  r |= x >> r > 0xffffffffffffffffn ? 64n : 0n;
  r |= x >> r > 0xffffffffn ? 32n : 0n;
  r |= x >> r > 0xffffn ? 16n : 0n;
  r |= x >> r > 0xffn ? 8n : 0n;
  const table = 0xf8f9f9faf9fdfafbf9fdfcfdfafbfcfef9fafdfafcfcfbfefafafcfbffffffffn;
  const shift = x >> r;
  const idx = shift < 256n ? (0x8421084210842108cc6318c6db6d54ben >> shift) & 0x1fn : 0n;
  r ^= (table >> (8n * (31n - idx))) & 0xffn;
  x = ((x << r) % MOD) >> 159n;

  let p = sar(96n, (3273285459638523848632254066296n + x) * x) + 24828157081833163892658089445524n;
  p = sar(96n, p * x) + 43456485725739037958740375743393n;
  p = sar(96n, p * x) - 11111509109440967052023855526967n;
  p = sar(96n, p * x) - 45023709667254063763336534515857n;
  p = sar(96n, p * x) - 14706773417378608786704636184526n;
  p = signed(p * x - (795164235651350426258249787498n << 96n));

  let q = 5573035233440673466300451813936n + x;
  q = 71694874799317883764090561454958n + sar(96n, x * q);
  q = 283447036172924575727196451306956n + sar(96n, x * q);
  q = 401686690394027663651624208769553n + sar(96n, x * q);
  q = 204048457590392012362485061816622n + sar(96n, x * q);
  q = 31853899698501571402653359427138n + sar(96n, x * q);
  q = 909429971244387300277376558375n + sar(96n, x * q);

  p = p / signed(q);
  p = signed(1677202110996718588342820967067443963516166n * p);
  p = signed(16597577552685614221487285958193947469193820559219878177908093499208371n * (159n - r) + p);
  p = signed(600920179829731861736702779321621459595472258049074101567377883020018308n + p);
  return sar(174n, p);
}

export interface RefereeParams {
  alphaInv: bigint;
  zClip: bigint;
  delta: bigint;
  payoffPerZ: bigint;
  habitHorizon: bigint;
  habitShortHorizon: bigint;
  meanHorizon: number;
  meanShortHorizon: number;
  sigmaHorizon: bigint;
  kappa: bigint;
  m: bigint;
  lambdaMax: bigint;
  onsBeta: bigint;
  onsA0: bigint;
  lapseLambda: bigint;
  lapseA: bigint;
  lapseEdgeFloor: bigint;
  sigmaMinPpm: bigint;
  tapeS: bigint;
  sigmaInitPpm: Record<string, bigint>;
}

// Builds the referee's parameters from config/params.json.
export function refereeParams(d: any): RefereeParams {
  const r = d.referee;
  const sigmaInitPpm: Record<string, bigint> = {};
  for (const e of Object.values<any>(d.feeds.entries)) sigmaInitPpm[e.id] = BigInt(e.sigmaInitPpm);
  return {
    alphaInv: BigInt(r.alphaInv),
    zClip: BigInt(r.zClipWad),
    delta: BigInt(r.deltaPointsWad),
    payoffPerZ: BigInt(d.match.payoffPerZ),
    habitHorizon: BigInt(r.habitHorizon),
    habitShortHorizon: BigInt(r.habitShortHorizon),
    meanHorizon: r.meanHorizon,
    meanShortHorizon: r.meanShortHorizon,
    sigmaHorizon: BigInt(r.sigmaHorizon),
    kappa: BigInt(r.kappaWad),
    m: BigInt(r.mPointsWad),
    lambdaMax: BigInt(r.lambdaMaxWad),
    onsBeta: BigInt(r.onsBetaWad),
    onsA0: BigInt(r.onsA0Wad),
    lapseLambda: BigInt(r.lapseLambdaWad),
    lapseA: BigInt(r.lapseA),
    lapseEdgeFloor: BigInt(r.lapseEdgeFloorWad),
    sigmaMinPpm: BigInt(d.match.sigmaMinPpm),
    tapeS: BigInt(d.timing.tapeS),
    sigmaInitPpm,
  };
}

export interface FighterState {
  n: bigint[];
  nShort: bigint[];
  logW: bigint;
  lambda: bigint;
  A: bigint;
  logL: bigint;
  rounds: number;
  kAtCert: number;
  lapsed: boolean;
}

export interface FeedState {
  meanZ: bigint;
  meanAbs: bigint;
  meanZShort: bigint;
  meanAbsShort: bigint;
  varReturn: bigint;
  count: number;
  seen: Set<bigint>;
}

export interface Verdict {
  skilled: boolean;
  lapsed: boolean;
  logW: bigint;
  lnBar: bigint;
  rounds: number;
  lambda: bigint;
  kAtCert: number;
}

export class Referee {
  private fighters = new Map<string, FighterState>();
  private feeds = new Map<string, FeedState>();
  private gamma: bigint;
  private gammaShort: bigint;
  private lnA: bigint;
  private sigmaFloor: bigint;

  constructor(private p: RefereeParams) {
    this.gamma = WAD - WAD / p.habitHorizon;
    this.gammaShort = WAD - WAD / p.habitShortHorizon;
    this.lnA = lnWad(p.lapseA * WAD);
    this.sigmaFloor = p.sigmaMinPpm * 10n ** 12n;
  }

  fighter(addr: string): FighterState {
    let s = this.fighters.get(addr);
    if (!s) {
      s = { n: [0n, 0n, 0n, 0n], nShort: [0n, 0n, 0n, 0n], logW: 0n, lambda: 0n, A: this.p.onsA0, logL: 0n, rounds: 0, kAtCert: 0, lapsed: false };
      this.fighters.set(addr, s);
    }
    return s;
  }

  feed(id: string): FeedState {
    let f = this.feeds.get(id);
    if (!f) {
      const sigma = this.p.sigmaInitPpm[id]! * 10n ** 12n;
      f = { meanZ: 0n, meanAbs: 0n, meanZShort: 0n, meanAbsShort: 0n, varReturn: (sigma * sigma) / WAD, count: 0, seen: new Set() };
      this.feeds.set(id, f);
    }
    return f;
  }

  sigmaWad(id: string): bigint {
    const s = isqrt(this.feed(id).varReturn * WAD);
    return s > this.sigmaFloor ? s : this.sigmaFloor;
  }

  lnBar(k: number): bigint {
    return lnWad(BigInt(k) * BigInt(k + 1) * this.p.alphaInv * WAD);
  }

  private means(meanZ: bigint, meanAbs: bigint, c: bigint): bigint[] {
    const k = this.p.payoffPerZ;
    const d = this.p.delta;
    return [clip(k * meanZ, -d, d), clip(-k * meanZ, -d, d), clip(k * (c - meanAbs), -d, d), clip(k * (meanAbs - c), -d, d)];
  }

  private payoffs(z: bigint, c: bigint): bigint[] {
    const k = this.p.payoffPerZ;
    const a = abs(z);
    return [k * z, -k * z, k * (c - a), k * (a - c)];
  }

  private driftD(s: FighterState): bigint {
    const nl = s.n.reduce((a, b) => a + b, 0n);
    const ns = s.nShort.reduce((a, b) => a + b, 0n);
    let total = 0n;
    for (let m = 0; m < 4; m++) {
      const fl = ((s.n[m]! + WAD) * WAD) / (nl + 4n * WAD);
      const fs = ((s.nShort[m]! + WAD) * WAD) / (ns + 4n * WAD);
      total += abs(fs - fl);
    }
    return total;
  }

  private driftE(f: FeedState, c: bigint): bigint {
    const lng = this.means(f.meanZ, f.meanAbs, c);
    const sht = this.means(f.meanZShort, f.meanAbsShort, c);
    let e = 0n;
    for (let m = 0; m < 4; m++) {
      const gap = abs(sht[m]! - lng[m]!);
      if (gap > e) e = gap;
    }
    return e;
  }

  private excessV(s: FighterState, f: FeedState, move: number, z: bigint, c: bigint): bigint {
    const zc = clip(z, -this.p.zClip, this.p.zClip);
    const mu = this.means(f.meanZ, f.meanAbs, c);
    const pay = this.payoffs(zc, c);
    const centred = pay.map((x, m) => x - mu[m]!);
    const total = s.n.reduce((a, b) => a + b, 0n);
    let sum = 0n;
    for (let m = 0; m < 4; m++) sum += (s.n[m]! + WAD) * centred[m]!;
    const baseline = sum / (total + 4n * WAD);
    const penalty = (((this.p.kappa * this.driftD(s)) / WAD) * this.driftE(f, c)) / WAD;
    const x = centred[move]! - baseline - penalty;
    return clip((x * WAD) / this.p.m, -WAD, WAD);
  }

  private bet(s: FighterState, v: bigint, k: number): void {
    const p = this.p;
    const term = WAD + (s.lambda * v) / WAD;
    s.logW += lnWad(term);
    const g = (v * WAD) / term;
    s.A += (g * g) / WAD;
    s.lambda = clip(s.lambda + (((p.onsBeta * g) / WAD) * WAD) / s.A, 0n, p.lambdaMax);
    s.rounds += 1;
    if (s.kAtCert === 0) {
      if (s.logW >= this.lnBar(k)) s.kAtCert = k;
    } else if (!s.lapsed) {
      const prev = s.logL > 0n ? s.logL : 0n;
      s.logL = prev + lnWad(WAD - (p.lapseLambda * (v - p.lapseEdgeFloor)) / WAD);
      if (s.logL >= this.lnA) s.lapsed = true;
    }
  }

  private update(addr: string, move: number, z: bigint, c: bigint, f: FeedState, k: number): void {
    const s = this.fighter(addr);
    this.bet(s, this.excessV(s, f, move, z, c), k);
    for (let m = 0; m < 4; m++) {
      const hit = m === move ? WAD : 0n;
      s.n[m] = (s.n[m]! * this.gamma) / WAD + hit;
      s.nShort[m] = (s.nShort[m]! * this.gammaShort) / WAD + hit;
    }
  }

  private updateFeed(f: FeedState, t: bigint, r: bigint, z: bigint): void {
    // Exactly once per tape, in any settlement order: a rated round's tape always reaches the feed.
    const tape = t / this.p.tapeS;
    if (f.seen.has(tape)) return;
    f.seen.add(tape);
    const zc = clip(z, -this.p.zClip, this.p.zClip);
    const a = abs(zc);
    f.count += 1;
    const longH = BigInt(Math.min(f.count, this.p.meanHorizon));
    const shortH = BigInt(Math.min(f.count, this.p.meanShortHorizon));
    f.meanZ += (zc - f.meanZ) / longH;
    f.meanAbs += (a - f.meanAbs) / longH;
    f.meanZShort += (zc - f.meanZShort) / shortH;
    f.meanAbsShort += (a - f.meanAbsShort) / shortH;
    f.varReturn += ((r * r) / WAD - f.varReturn) / this.p.sigmaHorizon;
  }

  // One scored, non-void round. Both fighters use the feed state from before this round.
  recordRound(feedId: string, t: bigint, p0: bigint, p1: bigint, c: bigint, a: string, moveA: number, kA: number, b: string, moveB: number, kB: number): void {
    const f = this.feed(feedId);
    const r = ((p1 - p0) * WAD) / p0;
    const z = (r * WAD) / this.sigmaWad(feedId);
    this.update(a, moveA, z, c, f, kA);
    this.update(b, moveB, z, c, f, kB);
    this.updateFeed(f, t, r, z);
  }

  // A missed or unrevealed round counts as v = -1. Habits and feed state do not change.
  recordForfeit(addr: string, k: number): void {
    this.bet(this.fighter(addr), -WAD, k);
  }

  verdictOf(addr: string, k: number): Verdict {
    const s = this.fighter(addr);
    return { skilled: s.kAtCert > 0, lapsed: s.lapsed, logW: s.logW, lnBar: this.lnBar(k), rounds: s.rounds, lambda: s.lambda, kAtCert: s.kAtCert };
  }
}
