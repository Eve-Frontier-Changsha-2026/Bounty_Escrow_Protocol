# Bounty Escrow Protocol — Integration Examples

Three compilable Move wrapper packages showing how upstream projects integrate with the `bounty_escrow` protocol.

## Examples

| Example | Upstream Project | Scenario | Stake | Max Claims |
|---------|-----------------|----------|-------|------------|
| [`intel_bounty`](./intel_bounty/) | Frontier Explorer Hub | Corporation posts intel bounty, Explorer submits data | None (0) | Multi-reporter |
| [`pvp_bounty`](./pvp_bounty/) | Fleet Command | Commander issues kill order, Mercenary executes | 10% of reward | 3 (competitive) |
| [`logistics_bounty`](./logistics_bounty/) | Tribal Governance DAO | DAO posts logistics task, Runner delivers | Security deposit | 1 (single runner) |

## Quick Start

```bash
# Build
cd examples/intel_bounty && sui move build

# Test
sui move test
```

Each package uses `bounty_escrow` as a local dependency. All tests use `test_scenario`.

## Switching to Published Dependency

Edit `Move.toml` — comment out the local line, uncomment the published address:

```toml
# bounty_escrow = { local = "../../bounty_escrow" }
bounty_escrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }
```

> **Note:** Published address only supports `sui move build`, not `sui move test` (tests need local source).

## What Each Example Covers

**Intel Bounty** — Happy path + expire (cleanup reward)
**PvP Bounty** — Happy path + abandon (desertion / stake forfeiture)
**Logistics Bounty** — Happy path + cancel -> withdrawal pattern (penalty + remaining)

Together, the three examples cover every public API in the protocol.

## ClaimTicket Key-Only Pattern

`ClaimTicket` has only the `key` ability (no `store`), so it cannot be passed to `transfer::public_transfer` outside the `bounty_escrow` module. Wrappers use `bounty::claim()` (non-composable) which handles internal transfer, or `bounty::claim_bounty()` (composable) when the ticket is consumed in the same transaction. See `pvp_bounty::mercenary` for both patterns.

## Generic Coin Type

All examples use `Coin<SUI>` for simplicity. The protocol supports any coin type via `Bounty<T>` — replace `SUI` with your custom coin type.

## TypeScript PTB Examples

See the [Integration Guide](../docs/integration-guide.md):
- S4 — Intel Bounty PTB flow
- S5 — PvP Bounty PTB flow
- S6 — Logistics Bounty PTB flow
- S7 — Events & Indexing
