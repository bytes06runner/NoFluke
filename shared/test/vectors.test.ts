// Replays shared/vectors/referee.json: TypeScript must match the Python reference bit for bit.
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { lnWad, Referee, refereeParams } from "../src/referee.ts";

const raw = (p: string) => JSON.parse(readFileSync(new URL(p, import.meta.url), "utf8"));
const P = refereeParams(raw("../../config/params.json"));
const V = raw("../vectors/referee.json");

const fighterJson = (s: ReturnType<Referee["fighter"]>) => ({
  n: s.n.map(String),
  nShort: s.nShort.map(String),
  logW: String(s.logW),
  lambda: String(s.lambda),
  A: String(s.A),
  logL: String(s.logL),
  rounds: s.rounds,
  kAtCert: s.kAtCert,
  lapsed: s.lapsed,
});

describe("referee vectors", () => {
  it("has the required counts", () => {
    expect(V.histories.length).toBeGreaterThanOrEqual(12);
    expect(V.histories.reduce((a: number, h: any) => a + h.steps.length, 0)).toBeGreaterThanOrEqual(80);
  });

  it("lnWad matches", () => {
    for (const c of V.lnWad) expect(lnWad(BigInt(c.x))).toBe(BigInt(c.y));
    expect(() => lnWad(0n)).toThrow();
  });

  it("bars match", () => {
    const r = new Referee(P);
    for (const c of V.bars) expect(r.lnBar(c.k)).toBe(BigInt(c.lnBar));
  });

  for (const h of V.histories) {
    it(`history: ${h.name}`, () => {
      const r = new Referee(P);
      for (const s of h.steps) {
        if (s.kind === "round") {
          r.recordRound(s.feed, BigInt(s.t), BigInt(s.p0), BigInt(s.p1), BigInt(s.c), s.a, s.moveA, s.kA, s.b, s.moveB, s.kB);
          const f = r.feed(s.feed);
          expect({
            meanZ: String(f.meanZ),
            meanAbs: String(f.meanAbs),
            meanZShort: String(f.meanZShort),
            meanAbsShort: String(f.meanAbsShort),
            varReturn: String(f.varReturn),
            count: f.count,
          }).toEqual(s.feedAfter);
        } else {
          r.recordForfeit(s.a, s.kA);
        }
        for (const [name, want] of Object.entries(s.fighters)) expect(fighterJson(r.fighter(name))).toEqual(want);
      }
    });
  }
});
