// Match rules in TypeScript: must match engine/nofluke/fightmath.py and FightMath.sol bit for bit.
const WAD = 10n ** 18n;
const PPM_SCALE = 10n ** 24n; // WAD * 1e6, because sigma is in parts per million
const BPS = 10_000n;

export const REASON = { KO: 0, HP: 1, FORFEIT: 2, DRAW: 3 } as const;

export interface Rules {
  hpStart: bigint;
  meterStart: bigint;
  meterCap: bigint;
  overdriveCost: bigint;
  meterWin: bigint;
  meterLoss: bigint;
  damageBase: bigint;
  diffCap: bigint;
  tie: bigint;
  regularRounds: number;
  maxRounds: number;
  sigmaMin: bigint;
  sigmaMax: bigint;
  payoffPerZ: bigint;
  counterNum: bigint;
  counterDen: bigint;
}

// Builds the match rules from config/params.json.
export function matchRules(d: any): Rules {
  const m = d.match;
  return {
    hpStart: BigInt(m.hpStart),
    meterStart: BigInt(m.meterStart),
    meterCap: BigInt(m.meterCap),
    overdriveCost: BigInt(m.overdriveCost),
    meterWin: BigInt(m.meterWin),
    meterLoss: BigInt(m.meterLoss),
    damageBase: BigInt(m.damageBase),
    diffCap: BigInt(m.damageDiffCapPoints) * WAD,
    tie: BigInt(m.tiePoints) * WAD,
    regularRounds: m.regularRounds,
    maxRounds: m.maxRounds,
    sigmaMin: BigInt(m.sigmaMinPpm),
    sigmaMax: BigInt(m.sigmaMaxPpm),
    payoffPerZ: BigInt(m.payoffPerZ),
    counterNum: BigInt(m.counterHitNumerator),
    counterDen: BigInt(m.counterHitDenominator),
  };
}

export interface Fighter {
  hp: bigint;
  meter: bigint;
}
export interface Command {
  move: number;
  read: number;
  overdrive: boolean;
}
export interface Side {
  pay: bigint;
  od: boolean;
  counter: boolean;
}
export interface RoundResult {
  z: bigint;
  damage: bigint;
  loser: number;
  a: Side;
  b: Side;
}
export interface MatchRound {
  p0: bigint;
  p1: bigint;
  voided: boolean;
  aMissing: boolean;
  bMissing: boolean;
  a: Command;
  b: Command;
}
export interface MatchResult {
  winner: number;
  reason: number;
  rounds: number;
  a: Fighter;
  b: Fighter;
}

const abs = (x: bigint) => (x < 0n ? -x : x);
const min = (a: bigint, b: bigint) => (a < b ? a : b);
const max = (a: bigint, b: bigint) => (a > b ? a : b);

export const moveType = (move: number) => (move <= 1 ? 0 : move - 1);
export const validMove = (move: number) => move <= 3;
export const validRead = (read: number) => read <= 2;

export function zWad(p0: bigint, p1: bigint, sigmaPpm: bigint): bigint {
  if (p0 <= 0n || p1 <= 0n) throw new Error("BadPrice");
  return ((p1 - p0) * PPM_SCALE) / (p0 * sigmaPpm);
}

export function isVoid(p0: bigint, conf0: bigint, expo0: bigint, p1: bigint, conf1: bigint, expo1: bigint, confCapBps: bigint): boolean {
  if (p0 <= 0n || p1 <= 0n || expo0 !== expo1) return true;
  if (confCapBps === 0n) return false;
  return conf0 * BPS > confCapBps * p0 || conf1 * BPS > confCapBps * p1;
}

export function basePayoff(rules: Rules, move: number, z: bigint, c: bigint): bigint {
  const k = rules.payoffPerZ;
  if (move === 0) return k * z;
  if (move === 1) return -k * z;
  if (move === 2) return k * (c - abs(z));
  return k * (abs(z) - c);
}

function side(rules: Rules, me: Fighter, cmd: Command, opp: Command, z: bigint, c: bigint): Side {
  const od = cmd.overdrive && me.meter >= rules.overdriveCost;
  if (od) me.meter -= rules.overdriveCost;
  let pay = basePayoff(rules, cmd.move, z, c);
  if (od) pay *= 2n;
  const counter = cmd.read === moveType(opp.move) && pay > 0n;
  if (counter) pay = (pay * rules.counterNum) / rules.counterDen;
  return { pay, od, counter };
}

export function resolveRound(rules: Rules, a: Fighter, b: Fighter, ca: Command, cb: Command, z: bigint, c: bigint, voided: boolean): RoundResult {
  const none = { pay: 0n, od: false, counter: false };
  if (voided) return { z, damage: 0n, loser: 0, a: none, b: none };
  const sa = side(rules, a, ca, cb, z, c);
  const sb = side(rules, b, cb, ca, z, c);
  const diff = abs(sa.pay - sb.pay);
  let damage = 0n;
  let loser = 0;
  if (diff < rules.tie) {
    a.meter = min(a.meter + rules.meterWin, rules.meterCap);
    b.meter = min(b.meter + rules.meterWin, rules.meterCap);
  } else {
    damage = rules.damageBase + (2n * min(diff, rules.diffCap)) / WAD;
    loser = sa.pay > sb.pay ? 2 : 1;
    const lose = loser === 2 ? b : a;
    const win = loser === 2 ? a : b;
    lose.hp = max(lose.hp - damage, 0n);
    lose.meter = min(lose.meter + rules.meterLoss, rules.meterCap);
    win.meter = min(win.meter + rules.meterWin, rules.meterCap);
  }
  return { z, damage, loser, a: sa, b: sb };
}

const forfeits = (missing: boolean, cmd: Command) => missing || !validMove(cmd.move) || !validRead(cmd.read);

export function resolveMatch(rules: Rules, sigmaPpm: bigint, c: bigint, rounds: MatchRound[]): MatchResult {
  if (sigmaPpm < rules.sigmaMin || sigmaPpm > rules.sigmaMax) throw new Error("SigmaBounds");
  const a = { hp: rules.hpStart, meter: rules.meterStart };
  const b = { hp: rules.hpStart, meter: rules.meterStart };
  let r = 0;
  for (;;) {
    if (r >= rules.maxRounds || (r >= rules.regularRounds && a.hp !== b.hp)) {
      if (a.hp === b.hp) return { winner: 0, reason: REASON.DRAW, rounds: r, a, b };
      return { winner: a.hp > b.hp ? 1 : 2, reason: REASON.HP, rounds: r, a, b };
    }
    if (r >= rounds.length) throw new Error("Truncated");
    const m = rounds[r]!;
    r += 1;
    const fa = forfeits(m.aMissing, m.a);
    const fb = forfeits(m.bMissing, m.b);
    if (fa || fb) return { winner: fa && fb ? 0 : fa ? 2 : 1, reason: REASON.FORFEIT, rounds: r, a, b };
    if (m.voided) continue;
    resolveRound(rules, a, b, m.a, m.b, zWad(m.p0, m.p1, sigmaPpm), c, false);
    if (a.hp === 0n || b.hp === 0n) return { winner: b.hp === 0n ? 1 : 2, reason: REASON.KO, rounds: r, a, b };
  }
}
