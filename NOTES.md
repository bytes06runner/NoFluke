# Current state

Last updated 2026-11-05 22:15 IST.

- **Working, tested locally:** referee v3 and FightMath (same vectors in Python, TypeScript and Solidity), FighterRegistry, DuelArena, BackingVault. Nothing is deployed.
- **Not started:** FamilyRegistrar, VerdictResolver, deploy script, World backend, Arkiv, Swarm, runner, fleet, web, `docs/scoring-rule.md`.
- **Validation:** the 10,000-seed run on all feeds is done, see `docs/reports/referee-validation.md`. It uses Binance data; a Pyth sample still needs the key.
- **Next step:** compare the deployed ENSv2 ABI with `contracts/lib/contracts-v2`. Source main has `UserRegistry.initialize(address,uint256)`, while the docs show a grants array. Read selectors with `cast code <address> --rpc-url <url>`: the last check failed because the flag order was wrong. Pin the submodule to the deployed commit if they differ.
- **Known to fix:** `docs/interfaces.md` is behind the code (createDuel has no vault amount, only the joiner can be vault-funded, `voidBoundary` replaces `voidRound`, `onSettle` has a forfeit flag). `feeds.*.stormCWad` and `sigmaInitPpm` still need the fitted values from validation. Real Pyth `parsePriceFeedUpdatesUnique` is unproven on Sepolia.
- **Before the fleet starts:** all contracts must be deployed together, because addresses are immutable and a redeploy resets verdict history.
- **Blocked on the owner:** Pyth API key, World clients, approval for testnet broadcasts and for registering `nofluke.eth`, Sepolia ETH top-up. See `docs/KEYS_NEEDED.md`.
- **Open questions for the owner:** ETHGlobal disclosure of the practice work, and money in the event build. See `docs/DECISIONS.md`.
- **Known practical issue:** GitHub rejects some pushes with transient server errors. `scripts/push.sh` scans and retries.
