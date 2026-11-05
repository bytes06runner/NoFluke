# Decisions (newest on top)

## 2026-11-05 21:50 IST
- **Rounds are retimed for Ethereum Sepolia.** Measured over 60 blocks: 58 gaps of 12 s and one of 24 s. An anchor must land before the bell, so the old 2 s margin would make honest fighters forfeit. New timing: 36 s contiguous tapes (3 blocks), 10 s commit, 26 s anchor margin. Each round's commit window sits inside the previous round's tape. One Pyth update serves as both a round's end and the next round's start, as the PLAN suggests. Expect about 75 rated rounds per hour per fighter, not the PLAN's 120, so the Fri 12:00 gate must use this rate.
- **Each fighter may be in only one active duel, enforced onchain.** New attack found while reasoning: play four overlapping duels with all four moves, settle the winning one first, and have only that one rated. Rating duplicates on one tape is also unsound, because repeated bets on one price move break the supermartingale. The practice build enforced this per family in the server only.
- **A missing reveal is not final for clients until the reveal deadline.** Pack review note: a withholder could reveal late onchain and win when an opponent's client had stopped committing. Clients keep committing until the duel is settled. The verdict side is already closed, since a forfeit counts v = -1, the worst possible value.
- **Open for the owner: money in the event build.** The pack's 2026-10-25 analysis recommended no money because of India's online gaming act. The PLAN and Prompt B both include stakes and a vault, so we build them as written, using test USDC only on Sepolia. This needs an owner decision and is not legal advice.

## 2026-11-05 21:45 IST
Four referee changes beyond the prompts. All are in `docs/interfaces.md`, and each gets a test.
- **The referee sets its own z scale.** A duel's `sigmaRef` is picked by its creator, so colluders could inflate z and "know" that Burst pays. The referee scales raw returns by its own forgetting estimate instead.
- **Feed state updates at most once per tape,** so many duels on one tape cannot overweight a single move.
- **Expired duels charge v = -1 to both fighters.** Otherwise a colluding pair could simply never settle a losing duel.
- **The lapse detector gets an edge floor.** With the plan's formula, a fighter whose edge falls to exactly zero never lapses, because zero edge is inside the detector's null. The value comes from validation.

Other changes:
- **No matchmaker key.** Fighters create duels and find them on Arkiv, per the PLAN, so the old signed ticket goes away.
- **`Approval` gains a nonce** so each approval works only once.
- **Interfaces go ahead as v1 without a stop.** The owner said to do the complete thing. Lane sign-off is still requested, and any change gets logged here.

## 2026-11-05 21:22 IST
- **Parent name is `nofluke` (config: `ens.parentLabel`), not `drafted-arena`.** The practice deployment irreversibly revoked the
  role that sets `drafted-arena.eth`'s subregistry, so it cannot host this build's registry. `nofluke` was available on Sepolia.
  The owner still has to approve the registration.
- **Arkiv writes use `executeBatch`.** PLAN says `mutateEntities`, but SDK 1.0.1 and the current docs use `executeBatch`.
- **Hermes needs `PYTH_API_KEY`.** Keyless calls return 401, so the runner and the validation data download both need it.
- **Pyth Core on Sepolia** (not Pyth Pro), because Core has the update-parsing interface the plan uses. Still to be proven with a real update.
- **Universal Resolver is the upgradable proxy** listed in the ENS deployments table. It is what a stock client should use.
- **ENSv2 subnames are owned tokens in a UserRegistry**, not resolver records, because the plan needs per-agent ownership and revocable names.

## 2026-11-05 21:12 IST
- docs/PLAN.md is ~/Downloads/afinallord.md ("Mumbai Build Plan for Claude Code", 2026-11-05), the only document with
  referee v2, the K(K+1)/alpha bar and Arkiv. "PLAN section 4" = "Statistical formulation v2"; "section 5" = "Architecture".
- The knowledge pack did not exist at kickoff; it is being generated (Prompt A) by a separate agent, so this build session
  never opens the practice repo. The pack is code-free and stays outside this repo.
- Owner: "do the complete thing": work proceeds without per-item "go" stops, but anything real still asks first
  (testnet broadcasts once per session, account creation, keys). Commits stay small and are pushed as soon as green; dates are never altered.
