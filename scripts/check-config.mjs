// Validates every file in config/ against its schema, and checks the rules a schema cannot express.
import { readFileSync } from "node:fs";
import Ajv from "ajv";

const read = (p) => JSON.parse(readFileSync(new URL(`../config/${p}`, import.meta.url), "utf8"));
const ajv = new Ajv({ allErrors: true, strict: false });
const pairs = [
  ["params.json", "schema/params.schema.json"],
  ["networks/sepolia.json", "schema/network.schema.json"],
  ["networks/arkiv.json", "schema/arkiv.schema.json"],
];

const problems = [];
for (const [file, schema] of pairs) {
  const validate = ajv.compile(read(schema));
  if (!validate(read(file))) {
    for (const e of validate.errors) problems.push(`${file} ${e.instancePath} ${e.message}`);
  }
}

const p = read("params.json");
const WAD = 10n ** 18n;
const r = p.referee;
// M must cover the largest |x|, so the clip on v never raises a loss. The drift penalty may clip, but only ever lowers v.
const zClip = BigInt(r.zClipWad);
const delta = BigInt(r.deltaPointsWad);
const maxAbsX = 2n * BigInt(p.match.payoffPerZ) * zClip + 2n * delta;
if (BigInt(r.mPointsWad) < maxAbsX) problems.push(`referee.mPointsWad ${r.mPointsWad} is below the largest |x| ${maxAbsX}`);
if (BigInt(r.lambdaMaxWad) >= WAD) problems.push("referee.lambdaMaxWad must stay below 1, or a full loss would wipe out wealth");
if (r.habitShortHorizon >= r.habitHorizon) problems.push("referee.habitShortHorizon must be below habitHorizon");
if (r.meanShortHorizon >= r.meanHorizon) problems.push("referee.meanShortHorizon must be below meanHorizon");
const t = p.timing;
// Tapes are contiguous, so a round's commit and anchor window sits inside the previous round's tape.
if (t.commitS + t.anchorMarginS > t.slotS) problems.push("timing: commit + anchor margin must fit in one slot");
if (t.tapeS !== t.slotS) problems.push("timing: tapes are contiguous, so the tape must equal the slot");
if (t.priceWindowS > t.revealGraceS) problems.push("timing: price window must not exceed the reveal grace");
if (t.settleGraceS >= t.refundGraceS) problems.push("timing: settle grace must be below the refund grace");
for (const name of p.feeds.order) if (!p.feeds.entries[name]) problems.push(`feeds.order names unknown feed ${name}`);

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log(`config ok: ${pairs.length} files validated`);
