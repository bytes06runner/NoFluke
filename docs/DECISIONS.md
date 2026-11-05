# Decisions (newest on top)

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
