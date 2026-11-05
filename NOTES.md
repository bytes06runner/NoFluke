# Current state

Last updated 2026-11-05 21:45 IST.

- **Working:** config and CI; referee v3 identical in Python, TypeScript and Solidity.
- **Not started:** FightMath, DuelArena, FighterRegistry, BackingVault, World backend, ENS contracts, Arkiv, Swarm, runner, web.
- **Blocked on the owner:** Pyth API key, World clients, approval for testnet broadcasts and for registering `nofluke.eth`. See `docs/KEYS_NEEDED.md`.
- **Open questions for the owner:** ETHGlobal disclosure of the practice work, and money in the event build. See `docs/DECISIONS.md`.
- **Parameters still provisional:** κ, the mean and habit short horizons, the lapse floor, storm C, and the initial sigmas. Validation will set them.
- **Known practical issue:** GitHub rejects some pushes with transient server errors. `scripts/push.sh` scans and retries.
