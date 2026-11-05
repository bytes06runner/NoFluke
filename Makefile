.PHONY: validate validate-quick install test test-py test-ts test-sol vectors lint-hardcode check-config fork deploy recompute e2e secrets

install:
	git submodule update --init --recursive
	pnpm install
	cd engine && uv sync

test: check-config lint-hardcode test-py test-ts test-sol

test-py:
	cd engine && uv run pytest -q

test-ts:
	pnpm --filter @nofluke/shared test

test-sol:
	cd contracts && forge test

# The same referee vectors must pass in Python, TypeScript and Solidity.
vectors:
	cd engine && uv run python -m nofluke.make_fight_vectors
	cd engine && uv run python -m nofluke.make_vectors
	cd engine && uv run pytest -q tests/test_vectors.py tests/test_fightmath.py
	pnpm --filter @nofluke/shared exec vitest run
	cd contracts && forge test --match-contract "Vectors"

lint-hardcode:
	node scripts/lint-hardcode.mjs

check-config:
	node scripts/check-config.mjs

fork:
	cd contracts && forge test --match-path 'test/fork/*'

deploy:
	bash scripts/deploy.sh

recompute:
	pnpm --filter @nofluke/server exec tsx src/recompute.ts

e2e:
	bash scripts/e2e.sh

secrets:
	gitleaks detect --no-banner --redact --source .

validate-quick:
	cd engine && uv run python -m sim.attacks --quick

validate:
	cd engine && uv run python -m sim.attacks --calibrate
