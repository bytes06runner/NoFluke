// Fails if source code holds a value that belongs in config/: an address, a URL, a 32-byte id, or a chain ID.
// Tests may hold fixtures, and imports and license headers are not values.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("..", import.meta.url));
const SCAN = ["contracts/src", "contracts/script", "engine/nofluke", "engine/sim", "shared/src", "server/src", "agents/src", "backend/src", "web/app", "web/lib", "web/components"];
const EXT = /\.(sol|ts|tsx|mjs|js|py)$/;
const SKIP_DIR = new Set(["node_modules", "generated", ".next", "__pycache__"]);

const network = JSON.parse(readFileSync(join(ROOT, "config/networks/sepolia.json"), "utf8"));
const arkiv = JSON.parse(readFileSync(join(ROOT, "config/networks/arkiv.json"), "utf8"));
const chainIds = [network.chainId, arkiv.chainId].map(String);

const RULES = [
  { name: "address", re: /\b0x[0-9a-fA-F]{40}\b/ },
  { name: "bytes32 id", re: /\b0x[0-9a-fA-F]{64}\b/ },
  { name: "url", re: /\b(?:https?|wss?):\/\/(?!www\.w3\.org)[^\s"'`)]+/ },
  { name: "chain id", re: new RegExp(`\\b(?:${chainIds.join("|")})\\b`) },
];
// A line may opt out by saying why, for example a type hash that is not a config value.
const ALLOW = /lint-hardcode-ok:/;

function* walk(dir) {
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const name of entries) {
    if (SKIP_DIR.has(name)) continue;
    const full = join(dir, name);
    if (statSync(full).isDirectory()) yield* walk(full);
    else if (EXT.test(name)) yield full;
  }
}

const hits = [];
let scanned = 0;
for (const dir of SCAN) {
  for (const file of walk(join(ROOT, dir))) {
    scanned++;
    readFileSync(file, "utf8").split("\n").forEach((line, i) => {
      if (ALLOW.test(line)) return;
      for (const { name, re } of RULES) {
        const m = line.match(re);
        if (m) hits.push(`${relative(ROOT, file)}:${i + 1} ${name}: ${m[0]}`);
      }
    });
  }
}

if (hits.length) {
  console.error(`Hardcoded values found. Move them to config/ and log the source in config/SOURCES.md:\n${hits.join("\n")}`);
  process.exit(1);
}
console.log(`lint-hardcode ok: ${scanned} files scanned`);
