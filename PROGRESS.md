# PROGRESS (log, newest entry on top; IST timestamps)

Rules: every significant step adds an entry: what changed, test output, tx hashes, the next step. Never edit old entries.

## Currently working on
- Claude Code (Srijeets-MacBook-Air-2): A1 FightMath, then A4 validation, then A2 DuelArena. Claimed 2026-11-05 21:45 IST.

---

## 2026-11-05 21:45 IST · Claude Code
**Changed:** monorepo scaffold, config with schemas, `lint-hardcode`, Makefile, CI, `docs/interfaces.md` v1, `SPONSORS.md` v1, `docs/KEYS_NEEDED.md`. Referee v3 in Python, then TypeScript, then Solidity.
**Tests:** pytest 38 passed. vitest 16 passed. forge 15 passed. Vectors match in all three languages: 13 histories, 960 steps, 18 `lnWad` cases. `lint-hardcode` and gitleaks clean.
**Found while building:** four referee holes the plan did not cover (sigma steering, tape stacking, never settling a losing duel, a lapse detector blind to zero edge) and one timing problem (12 s Sepolia blocks against a 2 s anchor margin). See `docs/DECISIONS.md`.
**Next:** FightMath in three languages, then referee validation on real data, then DuelArena.

---

## 2026-11-05 21:12 IST · Claude Code
**Changed:** repo cloned; docs/PLAN.md (the team's Mumbai plan) and prompts/00-rebuild-prompts.md added; log files started.
**Tests:** none yet.
**Next:** research (Arkiv, Pyth on Sepolia, USDC, ENSv2, World, prize rules) into config/SOURCES.md, then P0 scaffold.
