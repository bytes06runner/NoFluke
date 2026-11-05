# Interfaces (v1, for sign-off)

These formats are shared across the three lanes. Change them only with all three lanes agreeing, and log the change in `docs/DECISIONS.md`.

There is one chain, Ethereum Sepolia, and no gateway or oracle workflow. Every parameter comes from `config/params.json`. Contracts receive parameters as constructor immutables.

## Units

| Quantity | Type | Meaning |
| --- | --- | --- |
| WAD values | `int256` or `uint256` | Scaled by 10^18. This covers z, payoff points, λ, logW and bars. |
| Prices | `int64` plus exponent, as Pyth gives them | Big integers end to end. Never a float. |
| USDC | `uint256` | 6 decimals |
| Division | Truncates toward zero | Python must emulate this |

## Referee v3

The referee has no owner and no setters. Only DuelArena can write to it.

### State

| Per fighter | Type | Notes |
| --- | --- | --- |
| `n[4]`, `nShort[4]` | `uint128` WAD | Forgetting move counts, long and short horizon |
| `logW` | `int256` WAD | Evidence |
| `lambda`, `A` | `uint256` WAD | ONS bet and its accumulator, with A starting at 1 |
| `logL` | `int256` WAD | Lapse detector, starting at certification |
| `rounds` | `uint32` | Rated rounds, including forfeits |
| `kAtCert` | `uint32` | K when certified. 0 means not certified. |
| `lapsed` | `bool` | Sticky once set |

| Per feed | Type | Notes |
| --- | --- | --- |
| `meanZ`, `meanAbsZ` | `int256` WAD | Long-horizon means |
| `meanZShort`, `meanAbsZShort` | `int256` WAD | Short-horizon means |
| `varReturn` | `uint256` WAD | Forgetting variance of raw round returns |
| `count` | `uint64` | Feed updates so far |
| `lastT` | `uint64` | Start time of the last round that updated this feed |

### Functions

| Function | Access | Effect |
| --- | --- | --- |
| `recordRound(feedId, tStart, p0, p1, cWad, fighterA, moveA, fighterB, moveB)` | Arena only | One scored, non-void round. Updates both fighters using the feed state from before this round, then updates the feed. |
| `recordForfeit(fighter)` | Arena only | Applies v = −1 for a missed or unrevealed round. Habits and feed state do not change. |
| `verdictOf(fighter)` | View | Returns `(skilled, lapsed, logW, lnBar, rounds, lambda, kAtCert)` |
| `feedState(feedId)` | View | Per-feed state |
| `topFighter(feedId, rank)` | View | The rank-th Certified Skilled, not Lapsed fighter on that feed, or zero |

### What differs from PLAN referee v2

1. **Drift allowance:** x′ = x − κ·d·e, as Prompt B specifies.
2. **Forfeits:** v = −1.
3. **Verdict:** ever-crossed using K at that time, with `kAtCert` recorded.
4. **The referee sets its own z scale (new, not in the plan).**
   - `zRef = r / sqrt(varReturn)`, where r is the raw round return.
   - The match still uses the duel's `sigmaRef` for damage. The referee ignores it.
   - **Why:** `sigmaRef` is chosen by the duel's creator. Two colluding fighters could set it low to inflate z, then "know" that Burst pays. That is knowledge of the duel's settings, not of the market.
5. **The feed state updates at most once per tape (new).**
   - It updates only if `tStart ≥ lastT + tapeS`.
   - **Why:** otherwise many duels on one tape could overweight a single price move.
6. **Expired duels count against both fighters (new).**
   - `refundExpired` applies v = −1 to both, once for each regular round.
   - **Why:** otherwise a colluding pair could never settle a losing duel, and it would never count against them.
7. **Lapse floor (new).**
   - logL uses `v − lapseEdgeFloor`.
   - **Why:** with the plan's formula, a fighter whose edge fades to exactly zero never lapses, because zero edge is inside the detector's null. The floor value comes from validation.

## FightMath (library, three languages)

| Function | Behaviour |
| --- | --- |
| `moveType`, `validMove`, `validRead` | Move ids: 0 Strike Up, 1 Strike Down, 2 Guard, 3 Burst. Read ids: 0 Strike, 1 Guard, 2 Burst. |
| `checkSigma(sigmaRefPpm)` | Reverts outside the configured bounds |
| `zWad(p0, p1, sigmaRefPpm)` | Reverts on a non-positive price |
| `isVoid(p0, conf0, expo0, p1, conf1, expo1, confCapBps)` | Bad price, mismatched exponent, or confidence over the cap |
| `basePayoff(move, z, c)` | Payoffs: 10z, −10z, 10(C − abs z), 10(abs z − C) |
| `resolveRound(a, b, cmdA, cmdB, z, c, voided)` | Overdrive, Counter Hit, damage, meter, KO |
| `applyRound`, `needsRound`, `resolveMatch` | Exactly the regular rounds unless KO or forfeit; a sudden-death round if tied |

## FighterRegistry

| Function | Access | Effect |
| --- | --- | --- |
| `registerHuman(moveKey, nullifier, expiry, sig)` | Sender becomes the fighter; `sig` is from the World backend | Creates a family with K = 1 |
| `registerAgent(humanFighter, agent, moveKey, maxStake)` | FamilyRegistrar only | K + 1, permanently |
| `unbindAgent(agent)` | FamilyRegistrar only | Cap 0. K is unchanged. |
| `raiseAgentCap(agent, maxStake, approval, sig)` | Anyone submits | Needs a World approval |
| `lowerAgentCap(agent, maxStake)` | The agent's human | Lower only, no approval |
| `setMoveKey(moveKey)` | The fighter | Rotates the move key |

Views: `familyOf`, `familySize`, `isSameFamily`, `moveKeyOf`, `stakeCapOf`, `isRegistered`, `isUnbound`, `humanOf`.

Events: `HumanRegistered`, `AgentRegistered`, `AgentUnbound`, `AgentCapSet`, `MoveKeySet`.

## DuelArena

There is no matchmaker key. Duels are created by fighters and found on Arkiv.

| Function | Access | Notes |
| --- | --- | --- |
| `createDuel(feedId, sigmaRefPpm, stake, opponent, joinBy, permit, vaultAmount)` | Fighter | `opponent` zero means open to anyone |
| `joinDuel(id, permit, vaultAmount)` | Fighter | Rechecks both caps, family and unbound status; sets `startAt` |
| `cancel(id)` | Anyone, after `joinBy` | Refunds the creator |
| `anchor(id, round, cA, sigA, cB, sigB)` | Anyone | Skips a bad side; reverts only if nothing lands |
| `anchorOwn(id, round, side, c, sig)` | Anyone | Strict single-side path |
| `reveal(id, round, side, move, read, overdrive, salt)` | Anyone | Refused while the opponent can still anchor |
| `settle(id, priceUpdates)` | Anyone, payable | Scores with `parsePriceFeedUpdatesUnique`, then calls the referee |
| `voidRound(id, round, end, proof)` | Anyone, after the settle deadline | Needs Pyth's staleness proof |
| `refundExpired(id)` | Anyone, after the refund grace | Refunds both and charges forfeits to the referee |
| `claim()` | Pays the caller only | For payments a token refused |

Views: `duel`, `commitOf`, `revealOf`, `tStart`, `revealDeadline`, `settleDeadline`, `commitHash`, `commitDigest`, `stormC`, `roundVoided`, `owed`, `nextDuelId`, plus the immutables.

Events: `DuelCreated`, `DuelJoined`, `CommitAnchored`, `AnchorSkipped`, `MoveRevealed`, `RoundScored`, `DuelSettled`, `DuelCancelled`, `DuelRefunded`, `RoundVoided`, `PaymentDeferred`, `Claimed`.

## BackingVault

| Function | Access | Notes |
| --- | --- | --- |
| `deposit(fighter, assets)` | Anyone | Refused unless Skilled, not Lapsed, not unbound, and backing is allowed |
| `withdraw(fighter, shares)` | Holder; pays the caller only | Locked while a funded duel is live |
| `allowBacking(fighter, approval, sig)` | Anyone submits | Needs a World approval |
| `fundStake(fighter, duelId, amount, fighterOwn, opponent)` | Arena only | Enforces the Skilled check, caps and family rules |
| `onSettle(duelId, fighter, returned)` | Arena only | Accounting and fee |

Views: `vaultOf`, `sharesOf`, `assetsOf`, `rolling`, `highWaterMark(fighter)`.

## FamilyRegistrar (ENSv2)

This is the only holder of the registrar role on each family's registry.

| Function | Access | Effect |
| --- | --- | --- |
| `claimName(label, attestation, sig)` | A verified human | Deploys the family's `UserRegistry` through the verifiable factory, and registers `label.<parent>` |
| `enrollAgent(label, agent, moveKey, maxStake, approval, sig)` | Anyone submits | Needs a World approval. Registers `label.name.<parent>` and K + 1 in one transaction |
| `retireAgent(label)` | The human | Unregisters the name. K never falls |

The role bitmap given to name owners leaves out `ROLE_SET_RESOLVER`, so an owner cannot repoint an agent at a resolver that lies. Names expire at `season.endsAt`.

## VerdictResolver (ENSv2 custom resolver)

It implements `IExtendedResolver.resolve(name, data)` and answers `multicall` itself, so no batch can reach a stored record.

| Key on an agent name | Value |
| --- | --- |
| `drafted.verdict` | `Skilled`, `No edge yet` or `Lapsed` |
| `drafted.evidence` | logW and bar, in nats |
| `drafted.rounds` | Rated rounds |
| `drafted.family` | K, and K at certification |
| `drafted.eta` | Expected rounds to verdict at the measured g |
| `drafted.lapsed` | `true` or `false` |
| Other text keys | Forwarded to the human's Permissioned Resolver |
| `addr` | The agent's address, for every EVM coin type |

Wildcard names: `rank<n>.<feed slug>.<parent>` resolve to `topFighter(feedId, n)`.

### Agent records on the Permissioned Resolver

The agent key holds `ROLE_SET_TEXT` only for these keys, each scoped by EAC:

- `avatar`, `description`, `url`
- `agent-context` (ENSIP-26)
- `agent-endpoint[mcp]`, `agent-endpoint[a2a]`, `agent-endpoint[web]` (ENSIP-26)

The registry link `agent-registration[<ERC-7930 registry>][<agentId>]` (ENSIP-25) points at the ERC-8004 IdentityRegistry and is set when the agent is enrolled.

## World approvals

| EIP-712 type | Fields | Signed by |
| --- | --- | --- |
| `HumanAttestation` | `address fighter, uint256 nullifier, uint64 expiry` | World backend, after verifying IDKit |
| `Approval` | `address human, uint8 action, bytes32 paramsHash, uint64 expiry, uint256 nonce` | World backend, after a fresh Agent Pass step-up |

| Action | Value | `paramsHash` covers |
| --- | --- | --- |
| Enroll sibling | 1 | label, agent, moveKey, maxStake |
| Allow vault backing | 2 | fighter, per-duel cap |
| Raise agent cap | 3 | agent, new cap |

`nonce` is added to the prompt's `{human, action, paramsHash, expiry}` so an approval works only once. Each contract records used digests.

### Backend API

| Method and path | Purpose |
| --- | --- |
| `POST /world/idkit/rp-context` | Signed request context for IDKit |
| `POST /world/idkit/verify` | Verifies the proof server-side and returns a `HumanAttestation` |
| `POST /world/actions` | Agent asks for a protected action. Answers 401 with an RFC 9470-style step-up challenge |
| `GET /world/actions/:id/step-up` | Redirects to World with `max_age=0` and an essential `acr` |
| `GET /world/callback` | Validates state, nonce, PKCE, (iss, sub), `auth_time` and `acr` |
| `POST /world/actions/:id/device` | Device flow for headless agents |
| `POST /world/actions/:id/deny` | Live deny path: nothing changes |
| `GET /world/actions/:id` | Status, and the signed `Approval` once approved |

## Other EIP-712 types

| Type | Fields | Signed by |
| --- | --- | --- |
| `Commit` | `uint256 duelId, uint8 round, bytes32 commitHash` | Move key |
| `Permit` (EIP-2612) | The token's own domain | Funds wallet |

`commitHash = keccak256(abi.encode(duelId, round, fighter, move, read, overdrive, salt))`

## Arkiv entities (SDK 1.0.1, written with `executeBatch`)

| Entity | Owner | Indexed attributes | Expires |
| --- | --- | --- | --- |
| `challenge` | The fighter's wallet | `feed`, `stake`, `familyK`, `duelId`, `fighter` | At `joinBy` |
| `verdict` | Indexer; rechecked against `verdictOf` before each write | `ensName`, `fighter`, `feed`, `skilled`, `lapsed`, `familyK`, `rounds`, `logW`, `eta` | `season.endsAt` |
| `round` | Indexer | `fighter`, `duelId`, `round`, `feed`, `x`, `logW`, `lambda` | `season.endsAt` |
| `replay` | Indexer | `duelId`, `fighterA`, `fighterB`, `swarmRef` | `season.endsAt` |

Readers filter by owner, because anyone can write any shape to Arkiv. `swarmRef` is always an unencrypted reference.
