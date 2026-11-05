# Drafted Arena: real rebuild at ETHGlobal Mumbai (two prompts)

**How this works:**

1. **Prompt A** runs once, in the OLD practice repo. It writes a **knowledge pack**: plain-English specs,
   interface tables, maths, test-case lists, audit lessons, gotchas and sourced addresses. It contains no
   source code. The pack lives in `~/Desktop/drafted-knowledge/`, OUTSIDE the event repo, and is never
   committed.
2. **Prompt B** runs in the NEW event folder. Claude Code builds everything fresh from the knowledge pack and
   `docs/PLAN.md`, and never opens the old source files.

Old art (the Gemini fighters) is a pre-existing asset. The event build uses simple shapes or art generated
during the event; the later UI-polish account handles that.

---

## PROMPT A: knowledge extraction (paste in the OLD `drafted-arena` repo, and in a checkout of Priyanshu's branch)

```text
Read-only task. Do not modify this repo. Write a knowledge pack into ~/Desktop/drafted-knowledge/
(create it; it must be outside any git repo). The pack must contain NO source code: no Solidity,
TypeScript or Python, no copied functions and no code blocks longer than a one-line formula or
signature. Describe behaviour in plain English, tables and maths, the way a spec would.

First fetch and check out Priyanshu's latest work:
  git fetch https://github.com/bytes06runner/ragnarokv1.git claude/laughing-volta-xv2izy
Read its commits since our main, and include his ideas and changes in the pack as design notes.

Write these files:
1. 01-product.md: what the product is, the users, the pitch, the demo story, and what was cut and why.
2. 02-game-rules.md: every rule of a match.
   - Rounds and slot timing; commit, anchor and reveal windows; moves and the payoff formulas.
   - Read, Overdrive and meter; damage, KO and sudden death.
   - Void rule, forfeits, draws, rake, refunds.
   - Feed selection and calm-market fallback.
   - Every constant, with its value and why it has that value.
3. 03-referee-maths.md: the full luck-referee maths, as in docs/scoring-rule.md and the plan, with
   the validity argument, every parameter and the gate/lever results we measured (tables with numbers).
4. 04-interfaces.md: for each contract, server API, agent SDK and EIP-712 type: function and endpoint
   names, parameters, return values, events, errors and access rules. Tables only, no implementations.
5. 05-test-cases.md: a numbered list of every test scenario we had (contracts, referee, server, World,
   ENS, e2e), each with setup, action and expected result in one or two lines. Include all audit PoC
   scenarios.
6. 06-audit-lessons.md: every finding from every AUDIT-*.md, with severity, the bug in words, the
   attack, and the fix in words.
7. 07-gotchas.md: everything that cost us time:
   - CRE WASM lacking URL;
   - MockPyth not checking uniqueness;
   - fork broadcast overwriting deploy records;
   - Next router restoring the URL fragment;
   - gas estimate on Sepolia;
   - ENS address sets that don't match;
   - the 15-reads limit;
   - Mac sleep breaking tests;
   - and every other one in PROGRESS.md and NOTES.md.
8. 08-addresses-and-sources.md: every external address and URL we verified (Pyth, USDC, ENSv2 Sepolia
   set, Universal Resolver, ERC-8004 registries, World endpoints, Hermes), with source link and date.
   No keys, no .env values.
9. 09-ui-notes.md: screens, flows, design tokens (colours, fonts) and the FX timing table, in words and
   numbers only.
10. 10-priyanshu-changes.md: what his branch changed or proposed, and our recommendation per item.
11. INDEX.md: a one-page map of the pack.

When done, list the files and their sizes, and confirm that no file contains a code block of more than
one line.
```

---

## PROMPT B: the event build (paste in the NEW folder on the Desktop)

### 0. Ground rules

1. **Clean rebuild, Classic track.**
   - Build everything new in this repo.
   - Your references are only `docs/PLAN.md` (the team's plan) and the knowledge pack at
     `~/Desktop/drafted-knowledge/`. Read the pack, but never commit it, and never open, copy or vendor files
     from the old `drafted-arena` repo or Priyanshu's branch.
   - Third-party open-source libraries (OpenZeppelin, Solady, ENS contracts-v2, forge-std, viem, Pyth SDK,
     IDKit, Arkiv SDK) are fine as normal dependencies.
   - If a step would need old code, stop and tell me.
2. **Commits:**
   - Work as fast as you can, and commit each logical unit as soon as it is green: one feature, one test
     group, one config change.
   - Use descriptive messages, and push after each green step.
   - Do not hold finished work back to release it later. Do not batch hours of work into one commit, and
     never alter commit dates.
3. **Nothing hardcoded.**
   - Chain IDs, addresses, URLs, feed IDs, parameters and thresholds live in `config/` (schema-validated);
     sources go in `config/SOURCES.md`.
   - Secrets live only in `.env` and cast keystores.
   - `make lint-hardcode` is in CI and must stay green.
4. **Real, not simulated.**
   - Demo paths run on Ethereum Sepolia, Arkiv testnet, real Pyth prices, real World verification and real
     Swarm uploads.
   - Mocks are allowed only in unit tests.
   - Replays of real recorded prices go only in a tab labelled "Backup: replay".
5. **Access.** You may create accounts and request keys. Ask me first, giving the URL, numbered steps and the
   `.env` variable name. Never ask for a secret in chat. Confirm once per session before testnet broadcasts.
6. **Logs, updated after every significant step:**
   - `PROGRESS.md`: IST timestamps, newest first, listing what changed, test output, tx hashes and the next
     step.
   - `NOTES.md`: current state.
   - `AI_USAGE.md`: required by ETHGlobal.
   - `docs/DECISIONS.md`
   - `prompts/`: save each prompt we use.
7. **Workflow:**
   - Plan mode per work item, then wait for "go".
   - Failing test first for every money, referee, ENS-permission and World-approval rule; use
     `05-test-cases.md` as the checklist.
8. **Effort split:**
   - About 70%: referee maths, ENSv2 and World.
   - About 20%: Arkiv and Swarm.
   - At most 10%: visuals. A second Claude account will polish the UI/UX later, so build clean, functional
     screens on a design-token system that is easy to restyle.

### 1. First hour

1. Read `docs/PLAN.md` and the whole knowledge pack, starting with `INDEX.md`. Give me a 10-line summary of
   what we're building and your plan.
2. Scaffold the monorepo (PLAN P0), the config schema, `make` targets and CI.
3. Write `docs/interfaces.md` from `04-interfaces.md` plus the PLAN changes (single chain, Sepolia, referee
   v3, Arkiv), and stop for my sign-off.
4. Write `SPONSORS.md` (section 2) before any feature code.
5. List every login and key you need, with steps for each.

### 2. SPONSORS.md: our approach per partner

There are three slots: **World** (Agent Pass + IDKit count as one slot), **ENS** and **Arkiv**. The Swarm
bonus doesn't use a slot.

Each section of SPONSORS.md covers:

- the quoted prize rule;
- why our use is load-bearing;
- the user flow;
- the denied or alternative path;
- the repo files;
- the demo timestamp;
- the deliverable files and their status.

#### World: "more bots make you look less skilled"

**IDKit, Proof of Human.**

- Joining the ladder creates one family per person. Proof of Human is the minimum sufficient credential,
  because the sybil penalty only needs uniqueness.
- It is verified server-side, and the nullifier is the family key.
- Alternative path: cancelled or no credential means training only, with no name and no ladder.

**Agent Pass, with fresh human approval for three agent actions:**

1. **Enroll a sibling.** The screen shows the bar rising from ln(K(K+1)/α) to ln((K+1)(K+2)/α).
2. **Allow vault backing.**
3. **Raise an agent's spend cap.**

How the flow works:

- The agent calls our API and receives a step-up challenge (RFC 9470 style).
- The human approves on their phone. Headless agents use the device flow.
- The backend validates state, nonce, PKCE, (iss, sub), auth_time, and an essential acr of orb or orb-face.
  It then signs an EIP-712 approval `{human, action, paramsHash, expiry}`, which the contracts verify.

Every action has a live deny path in which nothing changes. Disclose that the event uses fake identities.
Write `docs/WORLD_DEBRIEF.md` (time to first success, friction, missing docs, top improvement) as you go.

#### ENS: "your name is your team, and the verdict can't be faked" (ENSv2 on Sepolia)

| ENSv2 feature | Our use |
|---|---|
| Own subname registry | Each human gets `name.drafted-arena.eth` with its own registry from the verifiable factory. Agents are subnames: `regime.name.drafted-arena.eth`. |
| Registrar roles | FamilyRegistrar is the only registrar. Every agent name needs a World approval and increments K. Owners can't change resolvers. |
| Enhanced Access Control | The agent key may edit only avatar, description, url and the ENSIP-26 records. It can never touch verdict keys. |
| Permissioned Resolver and custom resolver | Profile records sit on the human's Permissioned Resolver. VerdictResolver computes `drafted.verdict`, `.evidence`, `.rounds`, `.family`, `.eta` and `.lapsed` live from the arena contract, with no gateway. |
| Wildcard resolution | Live leaderboard names: `rank1.btc.drafted-arena.eth` always resolves to the current top Certified Skilled fighter on that feed. |
| Expiring and revocable subnames | Names expire at season end (params). `retireAgent` never lowers K. |
| Aliasing (SHOULD) | `agents.drafted-arena.eth` as a namespace alias. |
| AI agents bonus | ENSIP-26 `agent-context` and `agent-endpoint[...]`; ENSIP-25 `agent-registration` pointing at the ERC-8004 registry. Verify the exact keys against the specs and `ens-cli` first. |

Demo:

- Resolve an agent name in a stock ENS app and see "Skilled" next to a coin-flip bot's "No edge yet".
- Resolve `rank1.btc.drafted-arena.eth`.
- Approve a sibling: a new name appears, and K and the bar rise.

#### Arkiv (+ Swarm): "the lobby and the history don't belong to us" (Build on Arkiv, from scratch)

Judged 25% each on feedback, reach, why Arkiv, and how we use Arkiv.

**Entities:**

| Entity | Owner | Expiry |
|---|---|---|
| `challenge` | the fighter's own wallet | expires at the join deadline |
| `verdict` | the indexer, re-checked against `verdictOf` | season |
| `round` | the indexer | season |
| `replay` | the indexer | season |

**What users see:**

- Agents find duels by querying Arkiv, not our server.
- Unclaimed challenges expire on their own.
- The board runs the query "Skilled, K ≤ 3, BTC" on Arkiv.

**Swarm:** replay tapes are stored unencrypted; the plain reference goes in `replay.swarmRef`.

**Required files:**

- `/arkiv/schema.md`
- `/arkiv/friction.md` (log friction as it happens)
- `/arkiv/reach.md`
- `/arkiv/why-arkiv.md`
- `/arkiv/how-you-use-arkiv.md`
- `/arkiv/swarm.md`

The README has the writer wallet addresses and one runnable query.

#### Not chosen (one line each)

- **Arc:** it needs Studio and a second chain.
- **Chainlink:** the referee is onchain, so CRE would be decoration.
- **Hedera:** x402 would be a second product.
- **Uniswap, 1inch, Definitive:** no load-bearing link.

### 3. Luck referee v3 (main engineering focus)

Start from referee v2 in PLAN section 4: centred payoffs, forgetting habits, ONS betting, family bar
K(K+1)/α, the lapse detector and e-BH. Use `03-referee-maths.md` for the measured history.

**What "99% success" means.** Put this in the README and SPONSORS.md.

1. **Specificity ≥ 99%.** A fighter with no skill beyond their habits is certified with probability at most
   α = 0.01, at any stopping time.
   - This is guaranteed by Ville's inequality for stable habits.
   - For every attack below it is verified on replays of real recorded data, with the 95% upper bound ≤ 1%.
2. **Sensitivity ≥ 99%.** A fighter with growth at least g_min is certified within N99(g_min, K) rounds with
   probability ≥ 99%.
   - Measured, and printed as an operating-characteristic table.
   - Never claim it for arbitrarily small edges.

**New in v3:**

1. **Drift allowance.**
   - The null bias is Σ_m (p_t(m) − f̂_m)(μ_t(m) − μ̂_m).
   - By Hölder's inequality, |bias| ≤ ‖p − f̂‖₁ · max_m |μ_t(m) − μ̂_m|.
   - Use the predictable estimates d_t = ‖f̂^short − f̂^long‖₁ and e_t = max_m |μ̂^short_m − μ̂^long_m| (per
     feed; horizons from params).
   - Use x'_t = x_t − κ·d_t·e_t.
   - With stable habits d_t ≈ 0, so no power is lost.
   - Calibrate κ as the smallest value that keeps every attack ≤ α, and report the power cost.
   - Document this honestly in `docs/scoring-rule.md`.
2. **Unrevealed or forfeited rounds count as v_t = −1.** This blocks selective reveal.
3. **Opponent-free referee.** x depends only on the fighter's own move and z, so match-fixing moves money but
   never verdicts.
4. **Ever-crossed verdict.**
   - Skilled ⇔ max_s(logW_s − ln bar_s) ≥ 0, where bar_s uses K at time s.
   - The badge shows K at the time of certification.
   - The lapse detector can flip it to Lapsed.

**Attack catalogue.** Each one is a test. Use real recorded data, with 10,000 seeds per strategy. Results go
in `docs/reports/referee-validation.md`.

| # | Attack | Expected result |
|---|---|---|
| 1 | Stop at a lucky moment | ≤ α |
| 2 | Always Up / Down / Guard / Burst | ≤ α |
| 3 | Uniform random | ≤ α |
| 4 | Habit switcher; slow drifter | ≤ α |
| 5 | Periodic market-independent switching | ≤ α |
| 6 | Optimiser search (CMA-ES or random, 500+ candidates) over z-independent habit schedules | Best ≤ α at the 95% upper bound |
| 7 | Staggered 20-bot family | ≤ α |
| 8 | Selective reveal | Never Skilled |
| 9 | Match-fixing opponent | No verdict change |
| 10 | Void rounds | State unchanged |
| 11 | Overdrive and Read | No effect |
| 12 | Copycat | Not possible before commit; documented |
| 13 | Borrowed World ID | Disclosed limit; correlated-family flag |

**Power:** for planted-edge validation strategies (offline only), report N50, N90 and N99 at K = 2 and
K = 11, the measured g, and ONS vs the plug-in bet rule on the same seeds.

**Implementation:**

- **Order:** Python reference, then TypeScript, then Solidity, all identical integer WAD maths with Solady
  `lnWad`.
- **Vectors:** at least 80 rounds and 12 histories.
- **Gas:** report settle gas with both fighters' updates.
- **Interface:** `verdictOf(fighter)` returns `(skilled, lapsed, logW, lnBar, rounds, lambda, kAtCert)`.
- **Agent page:** shows `rounds ≈ ln(K(K+1)/α)/g` using the measured g.

### 4. Lanes (one Claude account each; interfaces frozen at hour 1.5)

| Lane | Owns | Notes |
|---|---|---|
| **A** | FightMath, referee v3, DuelArena, FighterRegistry, BackingVault, validation report | |
| **B** | World backend, FamilyRegistrar, VerdictResolver, wildcard rank names, Arkiv indexer, Swarm | |
| **C** | Match runner, agent fleet, web (`/board`, `/agent/[name]`, `/lobby`, `/demo`), Playwright, README, video | A later account polishes the UI/UX and the Colosseum theme |

### 5. Checkpoints (IST; submit by Sat 06:00, hard deadline 09:00)

| By | Done |
|---|---|
| Thu 22:30 | Scaffold, config, CI; interfaces signed off; SPONSORS.md v1 |
| Fri 02:00 | Referee v3 vectors identical in Python, TS and Solidity; attacks 1–11 green on a quick run |
| Fri 05:00 | DuelArena on Sepolia with real Pyth; **fleet live and unattended** (verdicts need wall-clock rounds) |
| Fri 09:00 | World: real approve and deny on all 3 actions |
| Fri 12:00 | **Gate:** measured g → demo choice (live Skilled, or live curve + ETA); validation report pushed |
| Fri 16:00 | ENSv2 names, VerdictResolver, EAC, wildcard rank names; viem test via the Universal Resolver |
| Fri 20:00 | Arkiv lobby, board, history; Swarm replays; `/arkiv/*.md` |
| Fri 22:00 | UI polish account takes over the visuals: Colosseum backdrop (stone arches, sunset sky, torches, sand floor, all in CSS/SVG/canvas), fighters, FX |
| Sat 02:00 | Feature freeze; Playwright `/demo` on live networks; README |
| Sat 05:00 | Video in our own voices (2–4 min); every sponsor checklist ticked |
| Sat 06:00 | Submit |

If anything slips, cut SHOULD items. Never cut the referee validation, the deny paths, or the fleet start
time.

### 6. Definition of done (paste the outputs into PROGRESS.md)

- **All green:** `make lint-hardcode`, `make vectors`, `forge test` (with Sepolia fork tests), `pytest`,
  `vitest`, gitleaks.
- **`make recompute`:** the offchain checker equals `verdictOf` for every fighter.
- **`docs/reports/referee-validation.md`:** every attack's 95% upper bound ≤ 1%; the N99 table; the measured g.
- **Live:** Sepolia contracts and Arkiv writers, with explorer links in the README.
- **World:** a real approve and deny for all 3 actions; `WORLD_DEBRIEF.md`.
- **ENS:** a stock ENS client resolves an agent name and `rank1.btc.drafted-arena.eth` live.
- **Arkiv:** all `/arkiv/*.md` files; a runnable query; `swarm.md`.
- **`/demo`:** Playwright passes on live networks; `docs/DEMO_SCRIPT.md` with Q&A.
- **Docs:** `AI_USAGE.md`, `prompts/`, `SPONSORS.md` and `PROGRESS.md` are current.

**Start:** read the plan and the pack, give the 10-line summary and the plan for the first hour, and wait for
"go".
