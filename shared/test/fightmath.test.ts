// Replays shared/vectors/fightmath.json: TypeScript must match the Python reference bit for bit.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { isVoid, matchRules, resolveMatch, resolveRound, zWad, type MatchRound } from "../src/fightmath.ts";

const raw = (p: string) => JSON.parse(readFileSync(new URL(p, import.meta.url), "utf8"));
const R = matchRules(raw("../../config/params.json"));
const V = raw("../vectors/fightmath.json");

function parseRounds(v: bigint[], at: number): { rounds: MatchRound[]; next: number } {
  const count = Number(v[at]);
  const rounds: MatchRound[] = [];
  let i = at + 1;
  for (let r = 0; r < count; r++) {
    rounds.push({
      p0: v[i]!,
      p1: v[i + 1]!,
      voided: v[i + 2] === 1n,
      aMissing: v[i + 3] === 1n,
      bMissing: v[i + 4] === 1n,
      a: { move: Number(v[i + 5]), read: Number(v[i + 6]), overdrive: v[i + 7] === 1n },
      b: { move: Number(v[i + 8]), read: Number(v[i + 9]), overdrive: v[i + 10] === 1n },
    });
    i += 11;
  }
  return { rounds, next: i };
}

describe("fightmath vectors", () => {
  it("rounds match", () => {
    const f = (V.rounds as string[]).map(BigInt);
    const w = V.roundWidth;
    for (let at = 0; at < f.length; at += w) {
      const v = f.slice(at, at + w);
      const a = { hp: v[4]!, meter: v[5]! };
      const b = { hp: v[6]!, meter: v[7]! };
      const z = zWad(v[0]!, v[1]!, v[2]!);
      const r = resolveRound(R, a, b, { move: Number(v[8]), read: Number(v[9]), overdrive: v[10] === 1n }, { move: Number(v[11]), read: Number(v[12]), overdrive: v[13] === 1n }, z, v[3]!, v[14] === 1n);
      expect([r.z, r.damage, BigInt(r.loser), r.a.pay, r.a.od ? 1n : 0n, r.a.counter ? 1n : 0n, r.b.pay, r.b.od ? 1n : 0n, r.b.counter ? 1n : 0n, a.hp, a.meter, b.hp, b.meter]).toEqual(v.slice(15));
    }
  });

  it("matches match", () => {
    for (const row of V.matches as string[][]) {
      const v = row.map(BigInt);
      const { rounds, next } = parseRounds(v, 2);
      const m = resolveMatch(R, v[0]!, v[1]!, rounds);
      expect([BigInt(m.winner), BigInt(m.reason), BigInt(m.rounds), m.a.hp, m.a.meter, m.b.hp, m.b.meter]).toEqual(v.slice(next));
    }
  });

  it("must-reject cases reject", () => {
    const names = { 1: "SigmaBounds", 2: "BadPrice", 3: "Truncated" } as Record<number, string>;
    for (const row of V.rejects as string[][]) {
      const v = row.map(BigInt);
      const { rounds, next } = parseRounds(v, 2);
      expect(() => resolveMatch(R, v[0]!, v[1]!, rounds)).toThrow(names[Number(v[next])]);
    }
  });

  it("void checks match", () => {
    for (const row of V.voids as string[][]) {
      const v = row.map(BigInt);
      expect(isVoid(v[0]!, v[1]!, v[2]!, v[3]!, v[4]!, v[5]!, v[6]!)).toBe(v[7] === 1n);
    }
  });
});
