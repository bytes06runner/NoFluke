# Our approach per partner (v1)

We're entering three partner slots: World, ENS and Arkiv. Swarm is a bonus on the Arkiv prize and doesn't use a slot. Prize rules are summarised here and linked to their source, so check the linked page for the exact wording.

## What "99% success" means

1. **Specificity of at least 99%.** A fighter with no skill beyond their habits is certified with probability at most α = 0.01, at any stopping time. Ville's inequality guarantees this for stable habits. For each attack in our catalogue, we verify it on replays of real recorded data, with the 95% upper bound at or below 1%.
2. **Sensitivity of at least 99%.** A fighter with growth of at least g_min is certified within N99(g_min, K) rounds with probability of at least 99%. This is measured and printed as a table. We never claim it for arbitrarily small edges.

Status: not measured yet. Results will go in `docs/reports/referee-validation.md`.

## World: "more bots make you look less skilled"

**Prizes:** Agent Pass (from scratch) and IDKit. [Prize page](https://ethglobal.com/events/mumbai/prizes/world)

**Rule summary:** show the full user journey, a denied, expired or cancelled path where the protected action does not happen, secure backend validation, and a short integration debrief.

**Why it's load-bearing:** the family bar `ln(K(K+1)/α)` is only meaningful if one person cannot be many people. Without uniqueness, a human could split bots into separate families and face a low bar for each. Without fresh approval, an agent could enrol siblings or take on risk with no person involved.

**User flow**

1. **Join the ladder.** IDKit Proof of Human, verified server-side. The nullifier is the family key, and Proof of Human is the minimum credential, because the penalty only needs uniqueness.
2. **Enroll a sibling.** The agent calls our API and gets a step-up challenge. The human sees the bar rising from `ln(K(K+1)/α)` to `ln((K+1)(K+2)/α)` and approves on their phone.
3. **Allow vault backing.** The human sees the caps and auto-stop rules, then approves.
4. **Raise an agent's cap.** The human sees the old and new cap, then approves.

Headless agents use the device flow. The backend validates state, nonce, PKCE, (iss, sub), `auth_time` and an essential `acr` of orb or orb-face, then signs an EIP-712 approval that the contracts verify.

**Denied or alternative paths**

| Moment | What happens |
| --- | --- |
| IDKit cancelled or no credential | Training only, with no name and no ladder |
| Enroll denied or expired | No subname, K unchanged, the bar does not move |
| Backing denied | The vault keeps refusing to fund |
| Cap raise denied | The cap stays where it was |

**Disclosure:** World's event setup uses fake identities, as its prize page states. Our README says so too.

**Repo files:** `backend/`, `contracts/src/FighterRegistry.sol`, `docs/WORLD_DEBRIEF.md`

**Demo timestamp:** 1:30–2:20

| Deliverable | Status |
| --- | --- |
| Real approve and deny on all three actions | Not started; needs the World keys |
| `docs/WORLD_DEBRIEF.md` | Not started |

## ENS: "your name is your team, and the verdict can't be faked"

**Prize:** Best Use of ENSv2. [Prize page](https://ethglobal.com/events/mumbai/prizes/ens)

**Rule summary:** built on ENSv2 on mainnet or Sepolia, with ENSv2 features central rather than cosmetic, a functional demo without hard-coded values, a live demo link, and open source.

**Why it's load-bearing:** the namespace is the family. K is the count of names ever issued, which sets the referee's bar. The verdict is computed by the resolver from the arena contract, with no gateway and no record anyone can hand-write.

| ENSv2 feature | Our use |
| --- | --- |
| Own subname registry | Each human gets `name.nofluke.eth` with a registry from the verifiable factory. Agents are subnames: `regime.name.nofluke.eth`. |
| Registrar roles | FamilyRegistrar is the only registrar. Every agent name needs a World approval and raises K. Owners can't change resolvers. |
| Enhanced Access Control | The agent key may edit only avatar, description, url and the ENSIP-26 records, never verdict keys. |
| Permissioned and custom resolvers | Profile records sit on the human's Permissioned Resolver. VerdictResolver computes `drafted.verdict`, `.evidence`, `.rounds`, `.family`, `.eta` and `.lapsed` live. |
| Wildcard resolution | `rank1.btc.nofluke.eth` resolves to the current top Certified Skilled fighter on that feed. |
| Expiring, revocable subnames | Names expire at season end. `retireAgent` never lowers K. |
| Agent records | ENSIP-26 `agent-context` and `agent-endpoint[...]`; ENSIP-25 `agent-registration` pointing at ERC-8004. |

**User flow:** resolve an agent name in a stock ENS app and see "Skilled" next to a coin-flip bot's "No edge yet". Resolve `rank1.btc.nofluke.eth`. Approve a sibling, and a new name appears as K and the bar rise.

**Denied or alternative paths:** a resolver swap reverts. An agent editing a verdict key reverts. A denied World approval means no name is issued.

**Repo files:** `contracts/src/FamilyRegistrar.sol`, `contracts/src/VerdictResolver.sol`, `contracts/test/fork/`

**Demo timestamp:** 2:20–2:50

| Deliverable | Status |
| --- | --- |
| `nofluke.eth` registered on Sepolia | Available; needs approval to register |
| Contracts and fork tests | Not started |
| Stock client resolves an agent name and a rank name | Not started |

## Arkiv (+ Swarm): "the lobby and the history don't belong to us"

**Prizes:** Build on Arkiv (from scratch), plus the Swarm bonus. [Prize page](https://ethglobal.com/events/mumbai/prizes/arkiv)

**Rule summary:** judged 25% each on friction feedback, reach, why Arkiv, and how we use Arkiv. Requires a schema file, an open-source licence, writer wallets and a runnable query in the README, and an AI disclosure. Installing the SDK without reading through it does not count.

**Why it's load-bearing:** on Postgres, we could hide, reorder or invent challenges and history. On Arkiv, each challenge is owned and signed by its fighter, expires on its own, and any client can query it without asking us. Agents find duels through Arkiv, not through our server.

**User flow:** an agent posts a challenge from its own wallet. Another agent finds it with an Arkiv query and joins onchain. The board runs the query "Skilled, K ≤ 3, BTC" on Arkiv. Replay tapes load from Swarm through a plain reference in `replay.swarmRef`.

**Denied or alternative paths:** an unclaimed challenge expires on its own. Entities not written by a known wallet are filtered out by readers. A verdict entity that disagrees with `verdictOf` is never written.

**Repo files:** `arkiv/`, `server/`

**Demo timestamp:** 2:20–2:50

| Deliverable | Status |
| --- | --- |
| `arkiv/schema.md`, `why-arkiv.md`, `how-you-use-arkiv.md`, `reach.md`, `swarm.md` | Not started |
| `arkiv/friction.md` | Started |
| README wallets and runnable query | Not started |
| Swarm batch ID and uploads | Needs a batch or a Bee node |

## Not chosen

- **Arc:** it needs Studio and a second chain.
- **Chainlink:** the referee is onchain, so CRE would be decoration.
- **Hedera:** x402 would be a second product.
- **Uniswap, 1inch, Definitive:** no load-bearing link.
