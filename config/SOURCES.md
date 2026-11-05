# Where every configured value came from

Each value in `config/` is listed here with its source and how it was checked. All entries were read on 2026-11-05 unless a row says otherwise. "Code" is the byte size `cast codesize` returned on Ethereum Sepolia, showing that a contract exists at that address.

## Ethereum Sepolia

| Value | Address or setting | Source | Check |
| --- | --- | --- | --- |
| Chain ID | 11155111 | Public chain registry | `eth_chainId` |
| Public RPC | ethereum-sepolia-rpc.publicnode.com | Tested directly | Serves current state; prunes old state |
| Archive RPC | sepolia.gateway.tenderly.co | Tested directly | Serves old state, for pinned fork tests |
| Pyth Core | 0x26DD80569a8B23768A1d80869Ed7339e07595E85 | https://docs.pyth.network/price-feeds/core/contract-addresses/evm | Code 680 |
| USDC (Circle) | 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238 | https://developers.circle.com/stablecoins/usdc-contract-addresses | Code 1798 |
| Hermes API | hermes.pyth.network | https://docs.pyth.network | Returns 401 without a key, so `PYTH_API_KEY` is required |
| Pyth history API | pyth.dourolabs.app/v1 | https://docs.pyth.network | Auth required, not yet called |

**Not yet verified:** `parsePriceFeedUpdatesUnique` with a real update on Sepolia. This needs `PYTH_API_KEY`.

## ENSv2 on Sepolia

All addresses below come from https://docs.ens.domains/learn/deployments.

| Value | Address | Code |
| --- | --- | --- |
| ETHRegistrar | 0xf633e7fc17e2bbe0d0965d18ec1821dcb754a3d3 | 8037 |
| ETHRegistry | 0xd4ebcbbdf463c9c45784603db0ddd499bc44a8b4 | 16000 |
| RootRegistry | 0xb458d6a3a77919449d03e7a6903c26827c1ec43f | 16000 |
| LabelStore | 0xed8246ff02203a4d4cb262bd78beaa7408a57cae | 1930 |
| VerifiableFactory | 0xda70306c98e97ece36f997a21368e53298572991 | 1524 |
| UserRegistryImpl | 0x9bd8a88719068d09ecee662f36c0e3856708366a | 18982 |
| PermissionedResolverImpl | 0x115eb53f0c60696633855f90b138178fb40b2b2c | 15608 |
| Universal Resolver (upgradable proxy) | 0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe | 2491 |
| MockUSDC (pays for ENS registration) | 0x240b0316df57887dbbe58b586508b19e633a14aa | 4309 |

The parent label `nofluke` reported `isAvailable` true on the ETHRegistrar at about block 12070451. It is not registered yet. See `docs/DECISIONS.md` for why this is not `drafted-arena`.

## ERC-8004 on Sepolia

Source: https://github.com/erc-8004/erc-8004-contracts (README).

| Value | Address | Code |
| --- | --- | --- |
| IdentityRegistry | 0x8004A818BFB912233c491871b3d84c89A494BD9e | 130 |
| ReputationRegistry | 0x8004B663056A597Dffe9eCcC1965A193B7388713 | 130 |

## Arkiv testnet (rabdi)

Sources: https://ethglobal.com/events/mumbai/prizes/arkiv and https://docs.arkiv.network/llms.txt.

| Value | Setting | Check |
| --- | --- | --- |
| Chain ID | 7794095 | `eth_chainId` returned 0x76edaf |
| RPC and WebSocket | rpc.rabdi.db-chain.testnet.arkiv.network | RPC answered; WebSocket not yet tested |
| Explorer | rabdi.explorer.arkiv.network | HTTP 200 |
| Indexer | indexer.rabdi.db-chain.testnet.arkiv.network | HTTP 200 |
| Faucet and access keys | hub.arkiv.network/faucet, /access-keys | Not yet used |
| SDK | `@arkiv-network/sdk` 1.0.1 (modified 2026-11-02) | npm registry |

## Standards used for ENS records

| Record | Exact key | Source |
| --- | --- | --- |
| Agent context | `agent-context` | https://docs.ens.domains/ensip/26 |
| Agent endpoints | `agent-endpoint[mcp]`, `agent-endpoint[a2a]`, `agent-endpoint[web]` | https://docs.ens.domains/ensip/26 |
| Registry link | `agent-registration[<ERC-7930 registry>][<agentId>]` | https://docs.ens.domains/ensip/25 |

## World

| Value | Source |
| --- | --- |
| Agent Pass guides (OIDC, step-up, testing) | https://auth.world.org/docs and https://auth.world.org/llms.txt |
| IDKit 4 integration | https://docs.world.org/world-id/idkit/integrate |
| Fake identities at the event | https://ethglobal.com/events/mumbai/prizes/world |
