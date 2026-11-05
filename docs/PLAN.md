# Drafted Arena: Mumbai Build Plan for Claude Code

Nov 5, 2026 · @TriNet

## Decision

We build **Drafted Arena** at ETHGlobal Mumbai, on **one chain (Ethereum Sepolia)**, for three partner slots: **World, ENS and Arkiv (+ the Swarm bonus)**. Blast Radius is dropped: its core value is an offchain proxy, its context-rollback step cannot actually reach a Claude Code or Cursor context window, and the Hedera judge already read it as an AI product with chains attached.

**The product in one breath.** Two fighters (people or AI agents) face the same live crypto price for five 20-second rounds and choose Strike, Guard or Burst. The contract settles the money from signed moves and Pyth prices. After every round the same contract updates a luck referee that asks one question: are this fighter's choices better than a monkey with the same habits? Only a fighter who clears that bar is called **Skilled**, and the bar rises for every extra bot the same human runs. The verdict is readable by anyone through the fighter's ENS name.

**What changed from the earlier brief (afinalwindrafted.md)**

| Earlier brief | This plan | Why |
| --- | --- | --- |
| Money on Arc, ENS on Sepolia, a signed gateway in between | Everything on Ethereum Sepolia | The gateway signer is a trusted poster again; one chain removes it and roughly a day of work |
| Arc as third sponsor | Arkiv (+ Swarm) as third sponsor | Arc requires starting in Arc Studio and Pyth on Arc is unverified; Arkiv judges already reacted well to us |
| ENS reads a verdict text record | The human's ENS name *is* the agent family; the subname count sets the sybil bar | ENS asks for ENSv2 to be central, with agents as namespaces |
| Referee v1 (habit baseline, plug-in bet size) | Referee v2 (section 4) | v1's validity claim breaks when a player changes habits; v2 fixes it and reaches verdicts with a better betting rule |
| CRE dropped because deploy access was missing | CRE still dropped | Chainlink now accepts simulation, but with the referee onchain CRE would be decoration |

**Will it work?** Yes, with two honest conditions. First, a live Skilled verdict needs hundreds of rounds, so the agent fleet must be running on live prices by about hour 8 (section 7). Second, a genuinely skilled agent only exists if the regime-reading edge holds on real data this weekend; if it does not, we say so on stage and show the referee correctly calling everyone "no edge yet", which is still the product working.

## Sponsor pitches

Each pitch is under 45 seconds: a story, the problem, what we do, and the one moment to show. Say them out loud; they are written to be spoken.

### Main stage (the opener for everyone)

> Give 1,000 people a coin and ask them to flip heads ten times in a row. One of them will do it. Now put that person on a leaderboard and call them a genius. That is every trading leaderboard today, and in India nine out of ten retail traders lost money last year, many of them copying someone who was just lucky.
>
> Drafted Arena is a game where luck can't climb. Two fighters face the same live market. After every round a referee, written into the contract itself, compares your choices with a monkey that has your exact habits. Beat the monkey consistently and you become Skilled. Run ten bots hoping one gets lucky, and the bar climbs steeply with every bot you add. Nobody posts the verdict: the contract works it out, and anyone can read it from your name.

### World

> One person with a hundred bots can always show you the lucky one. That is how fake trading gurus are made.
>
> In Drafted Arena, every fighter belongs to one real human, proven with World ID. When you add another bot, World asks *you*, the human, to approve it, and on screen you watch your own bar rise, because now you are "the best of two tries" instead of one. Say no, and nothing happens. The same fresh approval guards publishing your verdict and letting your agent spend more than its limit.
>
> Without World, the referee can be cheated by anyone with a laptop. With World, more bots make you look *less* skilled, not more.

**Show:** enroll a sibling, deny it (nothing changes), approve one (the bar line visibly moves up). **Why this credential:** Proof of Human, because the penalty only works if one person can't pretend to be two.

### ENS

> Today a trading bot is a random address. You can't tell who owns it, how many siblings it has, or whether it's any good.
>
> With us, your name is your team. You get `yourname.drafted-arena.eth`, and every agent you run is a name under it, like `regime.yourname.drafted-arena.eth`. ENS is the family register: the number of names you ever issued is the number the referee uses to raise your bar, and deleting a losing bot doesn't lower it. Your agent can change its own avatar and description, but only the arena can answer "is it Skilled?".
>
> Type the name into any ENS app and you get the live verdict, straight from the contract. No server in between, nothing we can fake.

**Show:** resolve an agent name in a normal ENS client and get "Skilled" next to a coin-flip bot's "No edge yet".

### Arkiv (+ Swarm)

> Every game has a lobby, and whoever runs the lobby decides who gets to play whom, and can quietly hide results.
>
> In Drafted Arena the lobby lives on Arkiv. A challenge is a record owned by the fighter who posted it, and it disappears by itself when its deadline passes. Agents find opponents by querying Arkiv directly, not by asking our server. Every fighter's history, round by round, sits on Arkiv too, so anyone can ask "show me the Skilled fighters with three bots or fewer" without our permission. Full fight replays live on Swarm, linked from each record.
>
> If we vanished tomorrow, the lobby and the history would still be there.

**Show:** an agent posts a challenge, another agent finds it with an Arkiv query and joins; an unclaimed challenge expires on its own; a public query lists Skilled fighters.

### The one-line answers to "is it really going to work?"

- **Is the game real skill?** Guessing up or down over 20 seconds is a coin flip, so the game doesn't reward it. It rewards spotting when the market is about to go wild or stay calm, which can be read in advance.
- **Can the referee be fooled?** Not by stopping at a lucky moment, not by always picking the same move, and not by running many bots. Each of those is a test in our repo.
- **What if nobody is actually Skilled this weekend?** Then the referee says so, which is the honest answer, and the product is still working exactly as promised.

## Ground rules for every Claude Code session

Paste this section, plus the section for the work item, at the start of each session in the **event repo** (a new, empty repo created after kickoff). Claude reads it fully before acting.

1. **Classic track, clean rebuild.** The practice repo `drafted-arena` is never copied, symlinked, cherry-picked or vendored into the event repo. Only knowledge carries over: this document, `docs/REBUILD_RUNBOOK.md`, the maths, interfaces and notes. If a step would copy a file, stop and say so.
2. **Real, not simulated.** Everything shown to judges comes from real chains (Sepolia, Arkiv testnet), real Pyth prices and real signatures. Mocks only inside unit tests. A replay of real recorded prices may appear only in a tab labelled "Backup: replay".
3. **Nothing hardcoded.** Chain IDs, addresses, URLs, feed IDs, parameters and thresholds live in `config/` (schema-validated, each address with its source URL). Secrets only in `.env` and cast keystores. `make lint-hardcode` stays green.
4. **Ask before acting on anything real.** Ask Srijeet or Priyanshu before any testnet broadcast, account creation, paid API use, or change to a contract that holds money. Never print or paste a key.
5. **Workflow.** Start each work item in plan mode and wait for "go". Write the failing test first for every money or referee rule. Commit small and often (ETHGlobal and several sponsors check commit history); push after every green step; never force-push.
6. **Keep state.** `PROGRESS.md` is the log (append test output and tx hashes), `NOTES.md` is current state and gotchas, `AI_USAGE.md` records what AI generated and what we changed. Claim your item under "Currently working on".
7. **Three lanes, three Claude accounts.** Lane A: contracts and referee. Lane B: World, ENS and Arkiv. Lane C: frontend, agents and demo. Shared interfaces are frozen in `docs/interfaces.md` within the first 90 minutes; changing them needs both other lanes to agree.

**First prompt of every session:**

```text
Read docs/PLAN.md (this document), docs/interfaces.md, NOTES.md and PROGRESS.md.
You are on Lane <A|B|C>, work item <ID>. Give me a 5-line status of that item,
then your plan: files you will touch, the tests you will write first, and the
evidence you will show at the end (test output, tx hashes, screenshots).
Stay in plan mode until I say "go".
```

## Statistical formulation v2: the luck referee

Referee v2 keeps the idea of v1 (a bet that you beat a monkey with your own habits, checked with Ville's inequality) but fixes three gaps a sharp judge could find, and adds two features. All of it still runs inside the contract at settlement.

### What v1 got wrong, and the fix

| # | Gap in v1 (brief section 4.1) | What an attacker or judge does | Fix in v2 |
| --- | --- | --- | --- |
| 1 | The proof says the excess has zero mean under "no skill". That holds only if the player's current move probabilities equal their past frequencies. | **Habit drift:** play Guard for 100 rounds, then switch to Burst forever. Burst has a higher average payoff, but the baseline still expects Guard, so the excess is positive with no market reading at all. | Centre each move's payoff on its public long-run average, and let habit frequencies forget slowly. The leftover bias becomes a product of two small, unrelated terms (proof sketch below), and a habit-switcher test proves it in simulation. |
| 2 | The family bar k/α with the *current* k. | **Staggered sybils:** register bots one at a time; the early ones faced a low bar. The real error is about α(1 + ln k), not α. | A shared bar of K(K+1)/α, where K counts every name ever issued in the family. This is exact for any order of registration. |
| 3 | Plug-in bet size (mean/variance) with a warm-up rule. It is close to aGRAPA from [Waudby-Smith and Ramdas](https://arxiv.org/abs/2010.09686), which is valid but has no worst-case growth guarantee and needs a tuned warm-up. | Not an attack; it is slow and twitchy in the first rounds. | Online Newton Step betting ([Cutkosky and Orabona](https://arxiv.org/abs/1802.06293)). It starts at a bet of 0, needs no warm-up, and its regret against the best fixed bet grows only like ln T ([analysis](https://arxiv.org/abs/2502.07774)). |
| + | Skilled is forever once reached. | Skill that fades still gates the vault. | A lapse detector (e-CUSUM from [Shin, Ramdas and Rinaldo](https://arxiv.org/abs/2203.03532)) flips the badge to "Lapsed" with a controlled false-alarm rate. |
| + | Each human is tested alone. | A board with 1,000 honest humans still shows about 10 false "Skilled" fighters at α = 0.01. | A board-level list built with e-BH ([Wang and Ramdas](https://arxiv.org/abs/2009.02824)), counted over verified humans, so sybils cannot grief it. |

The brief's claim that clipping the excess could break validity does not apply: with z clipped to ±3 and C between 0 and 3, any two moves differ by at most 60 points, so the clip never binds. v2 keeps a test that asserts this.

### The question the referee answers

In plain words: **do your moves know something about this round's market that your habits alone don't?** A fighter who picks moves from their own past pattern plus a dice roll, ignoring the market, is "no skill". A fighter who goes Burst when the storm meter rises is using the market, and that is the skill we certify.

Formally, for fighter i at round t: the move m\_t is committed onchain before the round's price window opens, and z\_t is the round's standardised price move. The null hypothesis is that m\_t is independent of the market given the fighter's own past moves.

### The algorithm, per settled non-void round

All quantities are computed from data that existed before round t, except z\_t and m\_t themselves.

**Step 1. Payoffs.** Only the base payoff counts (no Read, no Overdrive), with z clipped at ±3.

```latex
\mathrm{pay}_{U}(z)=10z,\quad \mathrm{pay}_{D}(z)=-10z,\quad \mathrm{pay}_{G}(z)=10(C-|z|),\quad \mathrm{pay}_{B}(z)=10(|z|-C)
```

**Step 2. Public move averages, per feed.** For each move, keep a slowly forgetting average of what that move would have paid on every settled round of the feed, clipped to ±Δ (Δ = 10 points). Because every payoff is built from z and |z|, two running averages per feed are enough.

```latex
\hat\mu_m(t-1)=\mathrm{clip}\big(\text{EW-mean}_{s<t}\,\mathrm{pay}_m(z_s),\,-\Delta,\,\Delta\big),\qquad c_m(z)=\mathrm{pay}_m(z)-\hat\mu_m(t-1)
```

**Step 3. Habit frequencies that forget.** The decay is γ = 1 − 1/H with H = 64 rounds, plus Laplace smoothing.

```latex
n_m \leftarrow \gamma\, n_m + \mathbb{1}[m_{t-1}=m],\qquad \hat f_m(t-1)=\frac{n_m+1}{\sum_k n_k+4}
```

**Step 4. Excess over the habit-matched monkey.** M = 80 covers the largest possible value (60 + 2Δ), so the clip never binds.

```latex
x_t = c_{m_t}(z_t)-\sum_m \hat f_m(t-1)\,c_m(z_t),\qquad v_t=x_t/M\in[-1,1]
```

**Step 5. Bet and wealth.** ONS chooses the bet λ, starting at 0 and kept in \[0, ½\].

```latex
\log W_t=\log W_{t-1}+\ln(1+\lambda_t v_t)
```

```latex
g_t=\frac{v_t}{1+\lambda_t v_t},\quad A_t=A_{t-1}+g_t^2\;(A_0=1),\quad \lambda_{t+1}=\mathrm{clip}\Big(\lambda_t+\tfrac{2}{2-\ln 3}\,\tfrac{g_t}{A_t},\;0,\;\tfrac12\Big)
```

**Step 6. Verdict.** K counts every fighter ever registered in the human's family, including the human (the ENS subname count). Skilled is "has ever crossed", so stopping early does not help anyone.

```latex
\text{Skilled}\iff \max_{s\le t}\big(\log W_s - \ln\tfrac{K_s(K_s+1)}{\alpha}\big)\ge 0,\qquad \alpha=0.01
```

### Why it is valid (the part to defend in Q&A)

1. **One fighter.** λ\_t uses only past rounds, so each factor 1 + λ\_t v\_t has conditional expectation 1 + λ\_t E\[v\_t | past\]. If that expectation is at most 0, W is a nonnegative supermartingale. Ville's inequality then gives P(W ever reaches 1/α) ≤ α, at any stopping time.
2. **Where the mean comes from.** Under the null, the expected excess equals the sum over moves of (p\_t(m) − f̂\_m) × (μ\_t(m) − μ̂\_m). Here p\_t is the fighter's true current move probability and μ\_t(m) is the move's true current average payoff. v1 had (p − f̂) × μ, which an attacker controls by switching toward the best-paying move. v2's term multiplies a habit change by a market-average error. Under the null those two are unrelated, so the attacker can no longer aim the bias. Forgetting habits (H = 64) also shrinks p − f̂ within a few dozen rounds of any switch.
3. **Be precise on stage.** v2 is exactly valid when habits are stable, and robust (measured, not assumed) when they change. The test suite reports the false-Skilled rate of habit switchers. The honest sentence: "exactly anytime-valid for stable habits; for habit switchers we measured X% over 10,000 replays".
4. **Family.** Member j joins when the family has j names, and from then on its bar is at least j(j+1)/α. The weights α/(j(j+1)) add up to α over all j, so the chance that any null member ever crosses is at most α, whatever the order or timing of registrations. A shared bar of K(K+1)/α is at least every member's own bar, so it stays valid. It also keeps the demo moment: approving a sibling visibly lifts the bar by ln((K+2)/K).

### Lapse detector (SHOULD)

A second, cheap process watches for the edge disappearing after Skilled. It uses a fixed small bet λ\_d = 0.2 against the fighter.

```latex
\log L_t=\max(\log L_{t-1},0)+\ln(1-\lambda_d v_t)
```

The badge turns to **Lapsed** and the vault stops when log L\_t ≥ ln A. Here A is the average number of rounds before a false alarm while the edge is still real (A = 500 from params). This replaces the vault's ad hoc "−2 standard deviation" rule with a guarantee from the e-detector framework.

### Board-level list (SHOULD)

The onchain gate stays per human. The `/board` "Certified Skilled" list runs e-BH over one e-value per verified human: each human's family score is the sum over members j of W\_j / (j(j+1)). That sum is a valid e-value because the weights add up to at most 1. The number of hypotheses is the number of World-verified humans, so bots cannot inflate it. e-BH controls the false discovery rate at α under any dependence between fighters.

### How long until a verdict (print this on every agent page)

For a small edge, the growth per round is about the squared mean of v divided by twice its mean square. Rounds to verdict are about the bar divided by that growth.

```latex
g\approx\frac{(\mathbb{E}v)^2}{2\,\mathbb{E}v^2},\qquad \text{rounds}\approx\frac{\ln\big(K(K+1)/\alpha\big)}{g}
```

Illustrative only, to be replaced by measured values. An agent averaging 3 points of excess with a 20-point spread has g ≈ 0.011 per round. Alone under a human (K = 2, bar ln 600 ≈ 6.4), it needs about 570 rounds plus a few hundred for ONS to settle. At 120 rounds per hour per fighter, that is roughly 5 to 7 hours. Measure the real g by hour 12 and decide the demo from the number, not from hope.

### Integer implementation (Solidity, TypeScript and Python identical)

| Stored per fighter | Type | Notes |
| --- | --- | --- |
| `n[4]` (forgetting move counts) | uint128 WAD | multiply by γ, then add 1 WAD to the played move |
| `logW`, `maxGap` | int256 WAD | maxGap = max of (logW − ln bar), recomputed when K changes |
| `lambda`, `A` | uint256 WAD | ONS state |
| `logL` | int256 WAD | lapse detector |
| `rounds`, `feedOfLastRound` | uint64, bytes32 | events record the feed per round |

Per feed: EW means of z and |z| (int256 WAD). Use Solady `FixedPointMathLib.lnWad` for ln(1 + y). `2/(2 − ln 3)` ≈ 2.2188 is a params constant (WAD), checked by a vector. Every parameter (α, γ or H, Δ, M, λ max, λ\_d, A, C, z clip) comes from params through constructor immutables. `verdictOf(fighter)` returns (skilled, lapsed, logW, lnBar, rounds, lambda). The offchain code in `fightmath.ts` and `fightmath.py` becomes a checker and must match the contract bit for bit.

### Referee tests (MUST, write them first)

- [ ] Vectors: at least 60 round cases and 10 full fighter histories, identical in Solidity, TypeScript and Python, including `lnWad` edge cases, ONS clamps at 0 and ½, and a family growing mid-history.
- [ ] The clip never binds: a fuzz over z, C, f̂ and μ̂ asserts |x| ≤ M.
- [ ] Farming strategies never reach Skilled across 10,000 seeded replays of real recorded tapes: always Up, always Guard, always Burst, uniform random, **habit switcher** (Guard then Burst), **slow drifter**, and **staggered 20-bot family**. Report each false-Skilled rate; each must be ≤ α within Monte Carlo error.
- [ ] Power: the regime reader is flagged Skilled within N rounds in at least 80% of replays; report N.
- [ ] A void round leaves all referee state unchanged; Overdrive and Read do not touch it.
- [ ] Registering a sibling raises the bar immediately in `verdictOf`, and revoking one never lowers it.
- [ ] Gas: settling a round with both fighters' referee updates stays under the params limit; report the number.

## Architecture

Everything that holds money, decides a verdict or names a fighter is a contract on Ethereum Sepolia. Offchain pieces only relay signed data, and anyone can replace them.

&#91;embedded content: system architecture · 3 layers, 1 chain\]

The match runner can disappear and players can still anchor their own commits and settle. Arkiv holds the open lobby and public history. The ENS resolver reads the referee directly, so no gateway or signer sits between a name and its verdict.

### Contracts

| Contract | Job | Key functions | Who can change it |
| --- | --- | --- | --- |
| FighterRegistry | One family per World-verified human; agent move keys; the family size K is an append-only count | `registerHuman(att)`, `registerAgent(human, agent, approval)`, `familyOf`, `familySize`, `isSameFamily` | Nobody. The attester key is set once and only signs attestations |
| DuelArena + Referee | USDC escrow, fixed 30-second slots, commit anchoring, reveals, permissionless settle with Pyth, referee v2 update per fighter per round | `createDuel`, `joinDuel`, `anchor`, `anchorOwn`, `reveal`, `settle`, `refundExpired`, `verdictOf` | Nobody; parameters are immutables from params |
| BackingVault | Backs only fighters that are Skilled and not Lapsed; 25% first-loss co-stake; 5% per duel; high-water-mark fee | `deposit`, `withdraw`, `fundStake`, `onSettle`, `highWaterMark(fighter)` (new view, closes the brief's gap) | Nobody |
| FamilyRegistrar | The only holder of the registrar role on each human's subname registry; issues `human.drafted-arena.eth` and agent subnames, and calls FighterRegistry in the same transaction | `claimName(att)`, `enrollAgent(label, agentKey, approval)`, `retireAgent(label)` | Nobody |
| VerdictResolver | A custom ENS resolver set on every agent subname. Verdict keys are computed live from `verdictOf`; profile keys fall through to the human's Permissioned Resolver | `text(name, key)`, `addr(name)`, `resolve(name, data)` | Nobody |

### ENSv2 design (what makes it central, not cosmetic)

- **The family is the namespace.** `drafted-arena.eth` has a registry of humans, and each human name gets its own subname registry deployed through the ENSv2 factory. Agents are subname tokens in it: `regime.srijeet.drafted-arena.eth`.
- **The count cannot be gamed.** Only FamilyRegistrar holds the registrar role, so every agent name passes through `enrollAgent`, which needs a World Agent Pass approval and increments K in FighterRegistry. Owners are not given the role to change resolvers, so nobody can point an agent at a resolver that lies.
- **Revocable, never forgettable.** `retireAgent` unregisters a subname, but K never decreases, so deleting a losing bot doesn't help. Agent names expire at season end (params) and can be renewed.
- **Enhanced Access Control.** The agent's key holds a text-record role scoped to `avatar`, `description` and `url` on the human's Permissioned Resolver. It can restyle itself but cannot touch `drafted.verdict`, which only the referee answers.
- **Agent records.** Publish the agent text records from ENSIP-26 and the registry link from ENSIP-25. Claude Code checks the exact keys against those specs before writing them.
- **Live keys served by VerdictResolver:** `drafted.verdict` (Skilled, No edge yet or Lapsed), `drafted.evidence` (logW and bar in nats), `drafted.rounds`, `drafted.family` (K), `drafted.eta` (expected rounds to verdict).

### Arkiv schema (MUST) and Swarm (SHOULD)

| Entity | Owner | Attributes people filter on | Expires | Read by |
| --- | --- | --- | --- | --- |
| `challenge` | the challenging fighter's wallet | feed, stake, arena, familyK, duelId | at the join deadline (params, about 5 minutes) | agents and the lobby page, to find and join duels |
| `verdict` (latest per fighter) | the indexer wallet; every value is rechecked against `verdictOf` | ensName, skilled, lapsed, familyK, rounds, logW, eta | season end | `/board` queries such as "skilled and familyK ≤ 3" |
| `round` (history) | the indexer wallet | fighter, duelId, round, feed, x, logW, lambda | season end | evidence curves on agent pages |
| `replay` | the indexer wallet | duelId, fighters, swarmRef | season end | the replay viewer, which loads the tape from Swarm |

Replays are public, so upload them to Swarm unencrypted and store the plain reference. Never put an encrypted Swarm reference in an Arkiv entity: Arkiv warns that it contains its decryption key. Batch writes with `mutateEntities` and query with cursor paging. The chain names differ between SDK versions, so Claude Code takes the RPC, chain ID (7794095) and SDK calls from the current Arkiv docs and the installed `.d.ts` files, and records the source in `config/SOURCES.md`.

**why-arkiv.md in one line:** on Postgres, the operator could hide, reorder or invent challenges and history; on Arkiv, every challenge is owned and signed by its fighter, expires on its own, and any client can query it without asking us.

### World flows

| Moment | Tool and credential | What the user sees | Denied or failed path |
| --- | --- | --- | --- |
| Join the ladder | IDKit, Proof of Human (the minimum that makes "one family per person" true) | Verify once, get `name.drafted-arena.eth` | Cancel or no credential: Training and free play only, no name, no ladder |
| Enroll another agent | Agent Pass fresh verification | Bar preview from ln(K(K+1)/α) to ln((K+1)(K+2)/α), then approve | Deny or expire: no subname, K unchanged, the bar does not move |
| Let a vault back my agent | Agent Pass | Shows the caps and the auto-stop rules | Deny: the vault keeps refusing `fundStake` |
| Raise an agent's stake cap | Agent Pass | Old cap, new cap | Deny: the cap stays |

Results are validated in the backend, which signs an EIP-712 approval that the contracts check. Event proofs use fake identities, as World's prize page states, and the README says so. Record time to first success and friction in `docs/WORLD_DEBRIEF.md`.

## Work items for Claude Code

Twelve work items across three lanes. The critical path is **P0 → A1 → A2 → C1**: the agent fleet must be playing on Sepolia by hour 8, because verdicts are earned in rounds and rounds take wall-clock time. Everything else runs beside it.

| ID | Lane | Priority | Item | Done when (evidence in PROGRESS.md) |
| --- | --- | --- | --- | --- |
| P0 | all | MUST | Scaffold, config, interfaces freeze | `make test` green, `make lint-hardcode` green, `interfaces.md` signed off by all three lanes |
| A1 | A | MUST | FightMath + referee v2 (Python, then TS, then Solidity) | Vectors identical in 3 languages; clip-never-binds fuzz passes |
| A2 | A | MUST | DuelArena + FighterRegistry on Sepolia with real Pyth | One full free match and one staked match settled; tx links; gas report |
| A3 | A | SHOULD | BackingVault + lapse detector + `highWaterMark` view | Attacker tests green; vault refuses a non-Skilled fighter on Sepolia |
| A4 | A | MUST | Referee validation on real recorded tapes | False-Skilled table for all farming strategies (≤ α) and the power number |
| B1 | B | MUST | World backend: IDKit Proof of Human + Agent Pass, attester | Real approve and real deny for all protected actions; debrief draft |
| B2 | B | MUST | ENSv2: FamilyRegistrar, subname registries, VerdictResolver | A viem test resolves an agent name through the Universal Resolver to the live verdict |
| B3 | B | MUST | Arkiv lobby + verdict/round entities; Swarm replays | Agent joins a duel found by an Arkiv query; challenge expires unclaimed; `/arkiv/*.md` files |
| C1 | C | MUST | Match runner + agent fleet live | Fleet running unattended; matches per hour, gas per round and void rate logged |
| C2 | C | MUST | Web: `/board`, `/agent/[name]`, lobby, `/demo` | Screens at 375 and 1440 px; no console errors |
| C3 | C | SHOULD | Canvas arena for a judge to play on a phone | A judge can play one match vs a house agent |
| C4 | C | MUST | Demo hardening: Playwright run, README, video, sponsor files | Playwright passes against live Sepolia; all checklists in section 9 ticked |

The polished fighting-game client from practice is SKIP-IF-LATE.

### Phase prompts (paste after the first prompt in section 3)

**P0. Scaffold**

```text
Create the monorepo from scratch (pnpm workspaces): contracts/ (Foundry, OpenZeppelin 5,
Solady, forge-std, ENS contracts-v2 as a dependency), engine/ (Python 3.12, pytest),
shared/ (fightmath.ts, types, eip712), server/ (match runner + indexer), agents/, web/
(Next.js), backend/ (World). Add config/params.json, config/networks/sepolia.json and
config/networks/arkiv.json with a JSON schema; config/SOURCES.md. Every address starts empty
and gets filled only after you read it from official docs or onchain and log the source:
Pyth on Sepolia, USDC on Sepolia (Circle), ENSv2 contracts on Sepolia, Arkiv RPC and chain
ID 7794095. Makefile: test, vectors, lint-hardcode, fork, deploy, recompute, e2e. Write
docs/interfaces.md: ABIs of all five contracts, the referee state struct, the Arkiv entity
schemas, the backend approval EIP-712 types. Stop and show me interfaces.md before code.
```

**A1. FightMath + referee v2**

```text
Implement docs/PLAN.md section 4 exactly. Order: engine/fightmath.py as the reference
(integer WAD maths, our own lnWad port of Solady), then shared/fightmath.ts with bigint,
then contracts/src/FightMath.sol and Referee.sol using Solady FixedPointMathLib.lnWad.
Rules: base payoff only; z clipped at 3; per-feed EW means of z and |z| clipped to ±Δ;
forgetting habit counts with H from params; centred excess x; M from params; ONS betting
with λ in [0, 1/2] and the constant 2/(2-ln3) from params; logW; bar ln(K(K+1)/α);
maxGap; lapse detector logL. Tests first: vectors (≥60 rounds, ≥10 histories, family
growing mid-history), |x| ≤ M fuzz, void round leaves state unchanged, Overdrive and
Read do not touch state. Show the vector table from all three languages.
```

**A2. DuelArena + FighterRegistry on Sepolia**

```text
Implement DuelArena (anchored commit-reveal, fixed 30 s slots, anchorOwn, reveal window,
missing commit or reveal forfeits, permissionless settle with Pyth
parsePriceFeedUpdatesUnique, void on wide confidence, exactly 5 rounds unless KO or
forfeit, sudden death, 2% rake, refund excess fee, permit-based stakes, stake 0 allowed)
and FighterRegistry (attested humans, agents only via FamilyRegistrar, append-only K,
isSameFamily on join). settle() calls Referee for both fighters per non-void round.
Reuse one price update at each round boundary (round r end = round r+1 start) to cut
Pyth verifications. Tests first, then a Sepolia fork test pinned to a block, then ask me
before broadcasting. Deliver: deploy script, addresses into config, one free and one
staked match settled live with tx links, gas per settle.
```

**A3. BackingVault**

```text
BackingVault per PLAN section 5: fundStake only if verdictOf says skilled and not lapsed;
fighter co-stake ≥25% first loss; ≤5% of vault per duel; one live duel; opponent not
Skilled and not same family (onchain); 20% daily loss cap; high-water-mark fee with a
public highWaterMark(fighter) view; internal accounting with virtual shares. Tests first,
including first-depositor inflation, same-family collusion, loss then recovery (no fee),
lapse stops funding. Then attack it yourself and report what you tried.
```

**A4. Referee validation on real data**

```text
In engine/sim: build 20 s rounds from recorded Pyth Benchmarks history (I download the
files). Strategies: always Up, always Guard, always Burst, uniform, habit switcher
(Guard 100 rounds then Burst), slow drifter, staggered 20-bot family, momentum, regime
reader. 10,000 seeded replays each. Print a table: false-Skilled rate with a 95% interval
per no-skill strategy (must be ≤ α), rounds-to-Skilled quantiles for the regime reader,
and measured g. Mark PASS or FAIL. Also compare ONS with the v1 plug-in rule on the same
seeds and report rounds-to-verdict for each.
```

**B1. World backend**

```text
backend/: IDKit Proof of Human verification (backend-signed request context, signal = the
fighter address) and World ID Agent Pass for three protected actions: enroll agent, allow
vault backing, raise stake cap. Validate every result server-side, never trust the client;
sign an EIP-712 approval {human, action, params hash, expiry} that contracts verify.
Tests for approved, denied, expired and cancelled paths. Log time to first success and
every friction point into docs/WORLD_DEBRIEF.md as you go.
```

**B2. ENSv2 family namespace**

```text
Using ENS contracts-v2 on Sepolia: a registry for drafted-arena.eth labels, a per-human
subname registry via the verifiable factory, FamilyRegistrar as the only ROLE_REGISTRAR
holder, and VerdictResolver (custom resolver) set on every agent subname. Owners get no
role to change the resolver. Agent keys get ROLE_SET_TEXT scoped to avatar, description
and url on the human's Permissioned Resolver. Verdict keys are computed from verdictOf.
Check ENSIP-25 and ENSIP-26 for the agent record keys before writing them. Tests: fork
tests for enroll, retire (K unchanged), a resolver swap attempt (reverts), an agent
editing a verdict key (reverts); a viem test resolving an agent name via the Universal
Resolver. Read the ENSv2 docs pages first; do not guess function names.
```

**B3. Arkiv + Swarm**

```text
server/indexer: watch DuelArena events and write Arkiv entities (challenge, verdict,
round, replay) per PLAN section 5 with @arkiv-network/sdk, batched, with explicit
expirations from params. Each verdict entity is checked against verdictOf before writing.
Agents post challenges themselves from their own wallets. Lobby and board pages read only
from Arkiv. Replays: upload the round tapes to Swarm unencrypted; store the reference in
the replay entity. Write /arkiv/schema.md, friction.md, reach.md, why-arkiv.md,
how-you-use-arkiv.md and /arkiv/swarm.md with real keys, queries and links.
```

**C1. Match runner + agent fleet**

```text
server/runner: creates or joins duels found on Arkiv, computes sigmaRef by the published
formula, collects move-key commits, anchors them before each slot, posts reveals, fetches
Pyth updates and calls settle with a small settler key. agents/: regime reader (uses the
storm meter), momentum, a 10-agent coin-flip family under a second human, and two
independent opponents under a third human. Run unattended with restart-on-crash, a gas
budget guard and a log of matches/hour, gas/round, settle success and void rate. Print
each agent's logW, bar and measured g every 15 minutes to PROGRESS.md.
```

**C2. Web**

```text
web/: /board (Naive vs Drafted toggle; naive ties broken by most recent win and shown as
"tied"), /agent/[name] (evidence curve crossing the bar, expected time to verdict, family
size, lapse state), /lobby (Arkiv challenges with expiry countdown), /demo (one page that
drives the 4-minute script in section 8, with a labelled Backup: replay tab). Every
onchain fact has a chip linking to Etherscan, the Arkiv explorer or an ENS app. No CRE or
simulation wording anywhere on the main path.
```

**C4. Demo hardening**

```text
One Playwright test runs the whole /demo path headless against live Sepolia and Arkiv.
README: pitch, architecture diagram, contract addresses with explorer links, referee in
plain English, one section per sponsor, honest limits, run-locally steps, AI usage.
Run the section 9 checklist and report every unticked item.
```

## Timeline to submission

Hour 0 is Thursday 19:00 IST. The fleet starts at hour 8 and runs until the video is recorded; we submit at hour 35 (Saturday 06:00), three hours before the hard deadline.

&#91;embedded content: build timeline · hours from Thu 19:00 IST\]

The hour-12 gate is the one decision that matters. Read each agent's measured g, compute the expected rounds to the bar, and choose the demo: a live Skilled agent, or the live curve plus its expected time to verdict.

**Checkpoints**

- **Hour 1.5:** `interfaces.md` frozen; all addresses sourced in `SOURCES.md`.
- **Hour 5:** referee vectors identical in three languages.
- **Hour 7:** first real match settled on Sepolia; gas per round measured against the Sepolia ETH budget.
- **Hour 8:** fleet live and unattended.
- **Hour 12:** gate on g; A4 table printed; World approve and deny both work.
- **Hour 18:** ENS name resolves to the live verdict; Arkiv lobby used by agents.
- **Hour 26:** feature freeze; everything after is hardening, README, sponsor files and the video.
- **Hour 33:** video recorded; every checklist in the next section ticked.

## Demo script (4 minutes) and judge Q&A

Lead with the referee, not the game: the game format has won before, and the referee is what nobody else has. Everything shown is live on Sepolia and Arkiv; the replay tab is opened only if something breaks.

| Time | Say | Show on `/demo` |
| --- | --- | --- |
| 0:00–0:25 | The coin story: 1,000 flippers, one "genius". "Every trading leaderboard works like this." | Naive board: a coin-flip bot is ranked first |
| 0:25–1:00 | "Same leaderboard, but each fighter is judged against a monkey with their own habits." | Toggle to Drafted: the coin flipper reads No edge yet; the regime reader reads Skilled, its live evidence curve crossing the bar |
| 1:00–1:30 | "Same win record, different truth." | Two agents with near-equal wins side by side; one curve crosses the bar, the other doesn't |
| 1:30–2:20 | "Now I try to cheat by adding bots." | Enroll 20 siblings: the World approval appears, deny it, nothing changes. Approve one: the bar line moves up live, and a new ENS name appears |
| 2:20–2:50 | "You don't need our app to check this." | Resolve `regime.<human>.drafted-arena.eth` in a stock ENS client: Skilled. Then the lobby: an agent's challenge on Arkiv, joined by another agent; an unclaimed one expiring |
| 2:50–3:35 | "Money follows proof." | A staked duel settling on Etherscan; the vault backing the Skilled agent and reverting on the coin-flip family |
| 3:35–4:00 | "Fight, get judged, and only the real ones get backed. No one posts the verdict: the contract works it out." | Contract addresses, ENS name, Arkiv query |

**If a judge has a phone free:** hand them the canvas arena to play one match against a house agent while you talk (C3). Skip it if C3 slipped.

### Judge Q&A (practice out loud)

- **"Isn't this just gambling?"** Stakes are optional and tiny; the product is the credential. Guessing up or down over 20 seconds is a coin flip and the game doesn't reward it. It rewards spotting calm versus storm, which can be read in advance.
- **"Who posts the verdict?"** Nobody. The contract updates it at settlement from signed moves and Pyth prices. The ENS name reads it directly from that contract.
- **"Can I fool it by stopping when I'm ahead?"** No. The evidence only counts if it would have held whenever you stopped. That's the mathematical guarantee, called Ville's inequality.
- **"Can I fool it by changing habits?"** We tested exactly that (habit switchers, slow drifters) on real price data. Here is the measured false-Skilled rate from those tests (quote the A4 number; never claim it before it is measured).
- **"Couldn't I borrow a friend's World ID?"** Yes, that's the limit by design: one person, one family. Today's demo uses World's test identities, as their rules state.
- **"Isn't skill here just volatility timing?"** Yes, and that's the point. We certify that your choices beat luck matched to your habits at this time scale. We don't claim trading profits.
- **"How long until a verdict?"** Show the agent page: the measured growth per round and the expected rounds to the bar.
- **"Why Arkiv and not a database?"** Challenges are owned by fighters, expire on their own, and any client can query them without us. If we vanish, the lobby and history remain.
- **"What did AI write?"** `AI_USAGE.md` and the prompts folder show it. We designed the rules, the statistics and the contract safety model, and reviewed every line that moves money.

## Risks, fallbacks and definition of done

The biggest risk is not code: it is whether enough live rounds, and a real edge, exist by demo time. Check both at hour 12 and decide from the numbers.

| Risk | Early warning | Fallback |
| --- | --- | --- |
| No agent reaches Skilled by demo time | Measured g at hour 12 implies more rounds than remain | Show the live curve and its expected time to verdict, plus the labelled replay tab; the referee saying "no edge yet" is still correct behaviour |
| The regime edge doesn't hold on this weekend's market | A4 power table or live g near zero | Switch the default feed to the most active of BTC, ETH, SOL; say honestly on stage that the market was calm |
| Sepolia gas or faucet limits | Gas per round × planned rounds exceeds the team's Sepolia ETH at hour 6 | Shared price updates at round boundaries; free (stake 0) duels for the fleet; fewer coin flippers running at once; ask the ETHGlobal faucet early |
| Pyth or USDC address wrong on Sepolia | Fork test fails at A2 | Addresses only from official pages with sources in `SOURCES.md`; fork test before any broadcast |
| ENSv2 contracts differ from the docs | B2 fork test fails | Keep the family logic in FighterRegistry (the gate still works) and serve verdicts via wildcard resolution on the parent name |
| World Agent Pass integration slower than planned | No real approve and deny by hour 18 | Keep IDKit for sign-up (its own prize) and show Agent Pass on one action only |
| Arkiv RPC or SDK friction | B3 writes failing | Note it in `friction.md` (25% of Arkiv's score); keep the lobby on Arkiv and move history to events if needed |
| A judge reads this as gambling | Questions about betting | Lead with the credential; stakes are optional and tiny |

### Definition of done (paste outputs into PROGRESS.md)

- [ ] `make lint-hardcode`, `make vectors` (referee v2 and `lnWad`), `forge test` (including Sepolia fork tests), `pytest`, `vitest`, gitleaks scan: all green
- [ ] `make recompute`: the offchain checker equals `verdictOf` for every fighter
- [ ] The A4 validation table: every no-skill strategy ≤ α; power and measured g reported
- [ ] Live on Sepolia: five contracts deployed, addresses in config, explorer links in the README
- [ ] The fleet has run unattended since hour 8; a soak summary in `docs/reports/soak.md`
- [ ] The Playwright demo test passes against live Sepolia and Arkiv

### Submission checklist per sponsor

**ETHGlobal (all prizes and Finalist)**

- [ ] Repo created after kickoff, steady commit history, no files from the practice repo
- [ ] `AI_USAGE.md` and `prompts/` complete; `docs/PLAN.md` included
- [ ] Demo video in our own voices, 2 to 4 minutes, not sped up
- [ ] Submitted by 06:00 IST Saturday (hard deadline 09:00)

**World (Agent Pass $5k, IDKit $2.5k)**

- [ ] Official Agent Pass integrated; full journey: request, completion, backend validation, protected action
- [ ] A denied, expired or cancelled path where the action does not happen, for each protected action
- [ ] IDKit with Proof of Human, verified in the backend, with one sentence on why it is the minimum sufficient credential
- [ ] `docs/WORLD_DEBRIEF.md`: time to first success, friction, missing docs, the one improvement that matters most

**ENS (Best Use of ENSv2, $7k)**

- [ ] Built on ENSv2 on Sepolia; the namespace, registrar roles, Enhanced Access Control and the custom resolver are central to the product
- [ ] Live demo link; nothing hardcoded in what resolves
- [ ] Open-source repo

**Arkiv (Build on Arkiv from scratch $4k, + Swarm $500)**

- [ ] Writes to the current Arkiv testnet with the SDK; lobby and board read from Arkiv
- [ ] README: writer wallet addresses and one query judges can run
- [ ] `/arkiv/schema.md`, `friction.md`, `reach.md`, `why-arkiv.md`, `how-you-use-arkiv.md`
- [ ] `/arkiv/swarm.md` with an entity key, its Swarm reference, the stamp batch ID, the Bee node used, the upload and read files, and the video timestamp
- [ ] Open-source license

## Sources

- [ETHGlobal Mumbai prizes](https://ethglobal.com/events/mumbai/prizes): World, ENS, Arkiv, Arc and Hedera track rules
- [Chainlink prize page](https://ethglobal.com/events/mumbai/prizes/chainlink): CRE simulation accepted
- [Waudby-Smith and Ramdas, Estimating means of bounded random variables by betting](https://arxiv.org/abs/2010.09686): testing by betting, aGRAPA
- [Cutkosky and Orabona, Black-box reductions for parameter-free online learning](https://arxiv.org/abs/1802.06293): ONS coin betting
- [Shekhar and Ramdas, Nonparametric two-sample testing by betting](https://arxiv.org/abs/2112.09162): ONS in testing by betting
- [Optimistic interior point methods for testing by betting](https://arxiv.org/abs/2502.07774): ONS logarithmic regret
- [Wang and Ramdas, False discovery rate control with e-values](https://arxiv.org/abs/2009.02824): e-BH under arbitrary dependence
- [Shin, Ramdas and Rinaldo, E-detectors](https://arxiv.org/abs/2203.03532): e-CUSUM and average-run-length control
- [ENSv2 Permissioned Registry](https://docs.ens.domains/ensv2/permissioned-registry), [Permissioned Resolver](https://docs.ens.domains/ensv2/permissioned-resolver), [Subnames](https://docs.ens.domains/ensv2/subnames), [Verifiable factory](https://docs.ens.domains/ensv2/verifiable-factory/), [Contract developer tutorial](https://docs.ens.domains/ensv2/tutorial-contract-developers)
- [Arkiv SDK skill notes](https://skills.sh/arkiv-network) and [Arkiv docs](https://docs.arkiv.network)
- Team inputs: `afinalwindrafted.md` (upgrade brief), Drafted Arena Final Build Plan (PDF), Blast Radius synthesis (PDF)
