# Logins and keys the build needs

Put every value in `.env` at the repo root, never in chat. `.env` is gitignored, and `.env.example` lists the names.

## Needed now

### 1. Pyth API key (blocks real-data validation and live prices)

Keyless Hermes calls now return 401. The key is free to get, so do not pick a paid plan.

1. Go to https://app.pyth.com (Pyth Terminal) and sign up.
2. Start the free trial and create an API key.
3. Add it to `.env` as `PYTH_API_KEY=...`.

### 2. World Agent Pass client (blocks the three approvals)

1. Go to https://auth.world.org/portal and sign in with Google.
2. Register an OIDC client:
   - **Callback URL:** `https://steed-unwieldy-carded.ngrok-free.dev/world/callback`
   - **Client authentication:** `client_secret_basic` (the portal default)
3. Copy the secret straight away, because the portal shows it only once.
4. Add to `.env`:
   - `WORLD_OIDC_CLIENT_ID=...`
   - `WORLD_OIDC_CLIENT_SECRET=...`

### 3. World ID app for IDKit (blocks joining the ladder)

1. Go to https://developer.worldcoin.org and create an app.
2. Enable World ID 4.0 if the portal shows the banner.
3. Add to `.env`:
   - `WORLD_APP_ID=...`
   - `WORLD_RP_ID=...`
   - `WORLD_RP_SIGNING_KEY=...`

### 4. ngrok authtoken (the old one was exposed)

1. Go to https://dashboard.ngrok.com/get-started/your-authtoken and rotate the token.
2. In your own terminal, run `ngrok config add-authtoken <new token>`.

## Needed by Friday morning

### 5. Arkiv writer wallets

I can generate these keys locally, so you don't need to do anything yet. I'll ask before writing to Arkiv.

1. The indexer wallet needs test funds from https://hub.arkiv.network/faucet.
2. If the public RPC rate-limits us, create a key at https://hub.arkiv.network/access-keys and add it as `ARKIV_ACCESS_KEY=...`.

### 6. Swarm postage batch

The Swarm bonus needs a postage batch ID, the wallet that bought it, and the Bee node we uploaded through.

- **Easiest:** ask the Swarm team at the event for a batch or a hosted upload endpoint, then add `SWARM_BEE_URL=...` and `SWARM_BATCH_ID=...`.
- **Otherwise:** run a Bee node ourselves. That takes longer and needs funded tokens, so I'd try the first option.

## Budget and approvals

| Item | Status | What I need from you |
| --- | --- | --- |
| Deployer wallet (`drafted-deployer`) | 0.0397 Sepolia ETH | Probably too little for all contracts plus a fleet, so plan a top-up |
| Settler wallet (`drafted-settler`) | 0.0104 Sepolia ETH | Needs much more: settling runs all night |
| Fleet wallets | Generated locally, not funded yet | Sepolia ETH and test USDC from a faucet |
| `nofluke.eth` on Sepolia | Available, not registered | Approval to register it |
| Testnet broadcasts | Not approved yet | One yes per session before the first broadcast |

I'll replace the top-up estimate with a measured number once settle gas is known.
