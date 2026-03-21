# Examples — Integration Wrapper Design Spec

> **Date:** 2026-03-21
> **Scope:** `examples/` directory in Bounty Escrow Protocol repo
> **Purpose:** Provide compilable, testable Move wrapper packages for three integration scenarios

---

## 1. Goal

Create three standalone Move packages under `examples/` that demonstrate how upstream projects integrate with `bounty_escrow`. Each package must:

- `sui move build` without errors
- `sui move test` with at least one passing happy-path test
- Serve as copy-paste-modify starting points for Explorer Hub, Fleet Command, and DAO

## 2. Directory Structure

```
examples/
├── README.md
├── intel_bounty/
│   ├── Move.toml
│   └── sources/
│       ├── intel_bounty.move
│       └── tests/intel_bounty_tests.move
├── pvp_bounty/
│   ├── Move.toml
│   └── sources/
│       ├── mercenary.move
│       └── tests/mercenary_tests.move
└── logistics_bounty/
    ├── Move.toml
    └── sources/
        ├── logistics.move
        └── tests/logistics_tests.move
```

## 3. Move.toml Strategy

Each package uses local path for dev, with commented published-address alternative:

```toml
[package]
name = "<package_name>"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
# Local development
BountyEscrow = { local = "../../bounty_escrow" }
# Production (testnet published):
# BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }

[addresses]
<package_name> = "0x0"
```

## 4. Package Specifications

### 4.1 Intel Bounty (`intel_bounty`)

**Scenario:** Corporation posts intel bounty → Explorer claims (zero stake) → Verifier approves → Explorer collects reward. Also covers expire path.

**Module:** `intel_bounty::intel_bounty`

| Function | Wraps | Notes |
|----------|-------|-------|
| `create_intel_bounty` | `bounty::create_bounty<SUI>` | `required_stake = 0`, configurable `max_reporters` |
| `accept_intel_bounty` | `bounty::claim_bounty<SUI>` | Zero-coin stake pattern |
| `verify_intel` | `bounty::approve_hunter<SUI>` | Requires `&VerifierCap`, `&Clock`, `&mut TxContext` |
| `collect_intel_reward` | `bounty::claim_reward_bounty<SUI>` | Explorer claims reward + zero stake back |
| `expire_intel_bounty` | `bounty::expire_bounty<SUI>` | Permissionless expire, caller gets cleanup reward |
| `intel_bounty_status` | `bounty::status<SUI>` | Read-only accessor |
| `intel_bounty_reward` | `bounty::reward_amount<SUI>` | Read-only accessor |

**Parameters:**

| Parameter | Value |
|-----------|-------|
| `required_stake` | `0` |
| `max_claims` | caller-specified (multi-reporter) |
| `grace_period` | `86_400_000` (1 day) |
| `cleanup_reward_bps` | `100u16` (1%) |

**Test:** `test_intel_happy_path` — create → claim (zero stake) → approve → claim_reward. Verify escrow drained, reward transferred.

### 4.2 PvP Bounty (`pvp_bounty`)

**Scenario:** Commander issues kill order → Mercenary accepts (stakes 10% of reward) → Battle Judge verifies → Mercenary collects. Also covers abandon (desertion) and cancel paths.

**Module:** `pvp_bounty::mercenary`

| Function | Wraps | Notes |
|----------|-------|-------|
| `issue_kill_order` | `bounty::create_bounty<SUI>` | Auto-calculates `required_stake = reward * STAKE_RATIO_BPS / 10000` |
| `accept_kill_order` | `bounty::claim_bounty<SUI>` | Mercenary stakes |
| `verify_kill` | `bounty::approve_hunter<SUI>` | Requires `&VerifierCap`, `&Clock`, `&mut TxContext` |
| `collect_bounty` | `bounty::claim_reward_bounty<SUI>` | Mercenary claims |
| `desert` | `bounty::abandon_bounty<SUI>` | Stake forfeited (desertion penalty) |
| `cancel_kill_order` | `bounty::cancel_bounty<SUI>` | Commander cancels |
| `kill_order_status` | `bounty::status<SUI>` | Read-only |
| `kill_order_reward` | `bounty::reward_amount<SUI>` | Read-only |
| `kill_order_stake` | `bounty::required_stake<SUI>` | Read-only |

**Parameters:**

| Parameter | Value |
|-----------|-------|
| `required_stake` | `reward_amount * STAKE_RATIO_BPS / 10000` (10%) |
| `max_claims` | `3` (hardcoded — max 3 mercenaries) |
| `grace_period` | `172_800_000` (2 days) |
| `cleanup_reward_bps` | `200u16` (2%) |

**Constant:** `STAKE_RATIO_BPS: u64 = 1000`

**Test:** `test_pvp_happy_path` — create → claim with stake → approve → claim_reward. Verify reward + stake returned. `test_pvp_abandon` — create → claim → abandon. Verify stake forfeited.

### 4.3 Logistics Bounty (`logistics_bounty`)

**Scenario:** DAO posts logistics task → Runner accepts (security deposit) → DAO Council verifies → Runner collects. Also covers cancel → withdrawal pattern.

**Module:** `logistics_bounty::logistics`

| Function | Wraps | Notes |
|----------|-------|-------|
| `post_logistics_task` | `bounty::create_bounty<SUI>` | Caller-specified `security_deposit` |
| `accept_logistics_task` | `bounty::claim_bounty<SUI>` | Runner deposits |
| `approve_delivery` | `bounty::approve_hunter<SUI>` | Requires `&VerifierCap`, `&Clock`, `&mut TxContext` |
| `collect_payment` | `bounty::claim_reward_bounty<SUI>` | Runner claims |
| `cancel_task` | `bounty::cancel_bounty<SUI>` | DAO cancels |
| `runner_withdraw` | `bounty::withdraw_penalty_bounty<SUI>` | Runner gets stake + penalty after cancel |
| `dao_withdraw_remaining` | `bounty::withdraw_remaining_bounty<SUI>` | DAO gets leftover after all runners withdraw |
| `task_status` | `bounty::status<SUI>` | Read-only |
| `task_reward` | `bounty::reward_amount<SUI>` | Read-only |

**Parameters:**

| Parameter | Value |
|-----------|-------|
| `required_stake` | caller-specified (`security_deposit`) |
| `max_claims` | `1` (single runner) |
| `grace_period` | `259_200_000` (3 days) |
| `cleanup_reward_bps` | `50u16` (0.5%) |

**Test:** `test_logistics_happy_path` — create → claim → approve → claim_reward. `test_logistics_cancel_withdraw` — create → claim → cancel → withdraw_penalty → withdraw_remaining.

## 5. Wrapper Design Principles

1. **Thin wrappers** — each function computes scenario-specific parameters, then delegates to `bounty_escrow::bounty` public API
2. **Use composable versions** — `_bounty` suffix functions that return values (e.g., `create_bounty` returns `Coin<T>` change, `claim_bounty` returns `(ClaimTicket, Coin<T>)`)
3. **No re-emitted events** — core protocol events are sufficient; wrappers don't add extra events
4. **No new structs with `key`** — wrappers don't create new on-chain objects; they only orchestrate existing `Bounty<T>`, `ClaimTicket`, `VerifierCap`
5. **SUI-only for simplicity** — all examples use `Coin<SUI>`; the generic `<T>` capability is mentioned in README
6. **Required imports** — each wrapper module needs both `bounty_escrow::bounty::{Self, Bounty, ClaimTicket}` and `bounty_escrow::verifier::VerifierCap` (VerifierCap lives in the verifier module, not bounty)

## 6. README.md Content

- One-paragraph overview of Bounty Escrow Protocol
- Table: which example matches which upstream project
- Quick start: `cd examples/intel_bounty && sui move build && sui move test`
- How to switch from local to published dependency
- Links to integration guide §4/§5/§6 for TypeScript PTB examples
- Links to integration guide §7 for event monitoring

## 7. Out of Scope

- TypeScript/PTB files — covered in integration guide
- Display/Publisher setup — not relevant to wrapper examples
- Cross-package shared modules — each example is fully independent
- Custom coin types — examples use SUI; README notes generic capability
- Deployment scripts — examples are reference code, not deployable packages
