# Examples Integration Wrappers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create three compilable, testable Move wrapper packages under `examples/` demonstrating how upstream projects integrate with `bounty_escrow`.

**Architecture:** Each example is an independent Move package with `bounty_escrow` as local dependency. Wrappers are thin — they compute scenario-specific parameters then delegate to `bounty_escrow::bounty` public API. Each includes a `test_scenario`-based happy-path test plus scenario-specific edge-case tests.

**Tech Stack:** Sui Move 2024 edition, `test_scenario` for testing

**Spec:** `docs/superpowers/specs/2026-03-21-examples-integration-wrappers-design.md`

---

### Task 1: Intel Bounty — Move.toml + Module

**Files:**
- Create: `examples/intel_bounty/Move.toml`
- Create: `examples/intel_bounty/sources/intel_bounty.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "intel_bounty"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
# Local development (clone repo, then build + test)
BountyEscrow = { local = "../../bounty_escrow" }
# Production (testnet published package):
# BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }

[addresses]
intel_bounty = "0x0"
```

- [ ] **Step 2: Create intel_bounty.move**

```move
/// Intel Bounty — Frontier Explorer Hub integration example.
///
/// Corporation posts intel bounty (zero stake) → Explorer claims →
/// Verifier approves → Explorer collects reward.
/// Also demonstrates the expire (cleanup) path.
///
/// TypeScript PTB examples: see docs/integration-guide.md §4
module intel_bounty::intel_bounty;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

const GRACE_PERIOD_MS: u64 = 86_400_000;   // 1 day
const CLEANUP_REWARD_BPS: u16 = 100;        // 1%

// ═══════════════════════════════════════════════
// Creator functions
// ═══════════════════════════════════════════════

/// Create an intel bounty. Zero stake required — explorers risk nothing.
/// `max_reporters`: how many explorers can claim (multi-reporter).
/// Returns change coin (composable).
public fun create_intel_bounty(
    title: String,
    description: String,
    payment: Coin<SUI>,
    reward_per_report: u64,
    max_reporters: u64,
    deadline: u64,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    bounty::create_bounty<SUI>(
        title,
        description,
        payment,
        reward_per_report,
        0,                    // required_stake = 0 (intel tasks)
        max_reporters,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        verifier_addr,
        clock,
        ctx,
    )
}

// ═══════════════════════════════════════════════
// Explorer (hunter) functions
// ═══════════════════════════════════════════════

/// Explorer accepts the bounty. Pass a zero-value coin for the stake.
/// Returns (ClaimTicket, change coin).
public fun accept_intel_bounty(
    bounty: &mut Bounty<SUI>,
    zero_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, zero_coin, clock, ctx)
}

/// Explorer collects reward after being approved.
public fun collect_intel_reward(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

// ═══════════════════════════════════════════════
// Verifier functions
// ═══════════════════════════════════════════════

/// Verifier approves an explorer's submission.
/// In production, add IntelReport quality checks here before approving.
public fun verify_intel(
    bounty: &mut Bounty<SUI>,
    explorer: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, explorer, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Cleanup (permissionless)
// ═══════════════════════════════════════════════

/// Expire a stale intel bounty. Anyone can call after deadline + grace.
/// Caller receives cleanup reward (1%).
public fun expire_intel_bounty(
    bounty: &mut Bounty<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    bounty::expire_bounty<SUI>(bounty, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun intel_bounty_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun intel_bounty_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `cd examples/intel_bounty && sui move build`
Expected: `BUILDING intel_bounty` → success

- [ ] **Step 4: Commit**

```bash
git add examples/intel_bounty/Move.toml examples/intel_bounty/sources/intel_bounty.move
git commit -m "feat(examples): intel bounty wrapper — zero-stake intel scenario"
```

---

### Task 2: Intel Bounty — Tests

**Files:**
- Create: `examples/intel_bounty/sources/tests/intel_bounty_tests.move`

- [ ] **Step 1: Write test file**

```move
#[test_only]
module intel_bounty::intel_bounty_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use intel_bounty::intel_bounty;

const CORPORATION: address = @0xA;
const VERIFIER: address = @0xB;
const EXPLORER: address = @0xC;
const CLEANUP_BOT: address = @0xD;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000; // +1 day

#[test]
fun test_intel_happy_path() {
    let mut scenario = ts::begin(CORPORATION);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. Corporation creates intel bounty (reward=500, max_reporters=2)
    ts::next_tx(&mut scenario, CORPORATION);
    let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let change = intel_bounty::create_intel_bounty(
        b"Intel: Scan Sector J-7".to_string(),
        b"Submit terrain data".to_string(),
        payment,
        500,           // reward per report
        2,             // max reporters
        DEADLINE,
        VERIFIER,
        &clock,
        ts::ctx(&mut scenario),
    );
    // change should be 0 (1000 payment = 500 * 2 reporters)
    coin::destroy_zero(change);

    // 2. Explorer accepts (zero stake)
    ts::next_tx(&mut scenario, EXPLORER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let zero_coin = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    let (ticket, stake_change) = intel_bounty::accept_intel_bounty(
        &mut bounty, zero_coin, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(stake_change);

    // Verify state
    assert!(intel_bounty::intel_bounty_status(&bounty) == constants::status_open());
    assert!(intel_bounty::intel_bounty_reward(&bounty) == 500);

    // Transfer ticket to EXPLORER (simulate what entry wrapper does)
    transfer::transfer(ticket, EXPLORER);
    ts::return_shared(bounty);

    // 3. Verifier approves explorer
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    intel_bounty::verify_intel(&mut bounty, EXPLORER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Explorer claims reward
    ts::next_tx(&mut scenario, EXPLORER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    intel_bounty::collect_intel_reward(&mut bounty, ticket, ts::ctx(&mut scenario));

    // Verify: escrow should have 500 left (one reporter slot remaining)
    assert!(bounty::escrow_value(&bounty) == 500);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_intel_expire() {
    let mut scenario = ts::begin(CORPORATION);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Corporation creates bounty
    ts::next_tx(&mut scenario, CORPORATION);
    let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    let change = intel_bounty::create_intel_bounty(
        b"Intel: Scan Sector K-2".to_string(),
        b"Submit threat data".to_string(),
        payment,
        1000,
        1,
        DEADLINE,
        VERIFIER,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Fast-forward past deadline + grace period
    clock::set_for_testing(&mut clock, DEADLINE + 86_400_000 + 1);

    // Cleanup bot expires the bounty
    ts::next_tx(&mut scenario, CLEANUP_BOT);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cleanup_reward = intel_bounty::expire_intel_bounty(
        &mut bounty, &clock, ts::ctx(&mut scenario),
    );

    // Verify expired state
    assert!(intel_bounty::intel_bounty_status(&bounty) == constants::status_expired());
    // Cleanup reward = 1000 * 100 / 10000 = 10
    assert!(coin::value(&cleanup_reward) == 10);

    transfer::public_transfer(cleanup_reward, CLEANUP_BOT);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

- [ ] **Step 2: Run tests**

Run: `cd examples/intel_bounty && sui move test`
Expected: `Running Move unit tests` → 2 tests passed

- [ ] **Step 3: Commit**

```bash
git add examples/intel_bounty/sources/tests/intel_bounty_tests.move
git commit -m "test(examples): intel bounty — happy path + expire tests"
```

---

### Task 3: PvP Bounty — Move.toml + Module

**Files:**
- Create: `examples/pvp_bounty/Move.toml`
- Create: `examples/pvp_bounty/sources/mercenary.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "pvp_bounty"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
# Local development (clone repo, then build + test)
BountyEscrow = { local = "../../bounty_escrow" }
# Production (testnet published package):
# BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }

[addresses]
pvp_bounty = "0x0"
```

- [ ] **Step 2: Create mercenary.move**

```move
/// PvP Bounty — Fleet Command integration example.
///
/// Commander issues kill order → Mercenary accepts (10% stake) →
/// Battle Judge verifies → Mercenary collects reward + stake.
/// Also demonstrates abandon (desertion) and cancel paths.
///
/// TypeScript PTB examples: see docs/integration-guide.md §5
module pvp_bounty::mercenary;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

/// Mercenary must stake 10% of reward as commitment
const STAKE_RATIO_BPS: u64 = 1000;         // 10%
const MAX_MERCENARIES: u64 = 3;
const GRACE_PERIOD_MS: u64 = 172_800_000;  // 2 days
const CLEANUP_REWARD_BPS: u16 = 200;        // 2%

// ═══════════════════════════════════════════════
// Commander (creator) functions
// ═══════════════════════════════════════════════

/// Issue a kill order. Auto-calculates required stake = reward × 10%.
/// Returns change coin (composable).
public fun issue_kill_order(
    target_name: String,
    description: String,
    payment: Coin<SUI>,
    reward: u64,
    deadline: u64,
    battle_judge: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let stake = reward * STAKE_RATIO_BPS / 10000;

    bounty::create_bounty<SUI>(
        target_name,
        description,
        payment,
        reward,
        stake,
        MAX_MERCENARIES,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        battle_judge,
        clock,
        ctx,
    )
}

/// Commander cancels the kill order.
/// If mercenaries have claimed, triggers withdrawal pattern.
public fun cancel_kill_order(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::cancel_bounty<SUI>(bounty, ctx)
}

// ═══════════════════════════════════════════════
// Mercenary (hunter) functions
// ═══════════════════════════════════════════════

/// Mercenary accepts the kill order with stake.
/// Returns (ClaimTicket, change coin).
public fun accept_kill_order(
    bounty: &mut Bounty<SUI>,
    stake_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, stake_coin, clock, ctx)
}

/// Mercenary collects reward after battle judge approval.
public fun collect_bounty(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

/// Mercenary deserts — forfeits stake to commander.
public fun desert(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::abandon_bounty<SUI>(bounty, ticket, clock, ctx)
}

// ═══════════════════════════════════════════════
// Battle Judge (verifier) functions
// ═══════════════════════════════════════════════

/// Battle Judge verifies a kill.
/// In production, add kill-proof validation here.
public fun verify_kill(
    bounty: &mut Bounty<SUI>,
    mercenary: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, mercenary, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun kill_order_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun kill_order_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}

public fun kill_order_stake(bounty: &Bounty<SUI>): u64 {
    bounty::required_stake<SUI>(bounty)
}
```

- [ ] **Step 3: Build**

Run: `cd examples/pvp_bounty && sui move build`
Expected: success

- [ ] **Step 4: Commit**

```bash
git add examples/pvp_bounty/Move.toml examples/pvp_bounty/sources/mercenary.move
git commit -m "feat(examples): pvp bounty wrapper — kill order + stake scenario"
```

---

### Task 4: PvP Bounty — Tests

**Files:**
- Create: `examples/pvp_bounty/sources/tests/mercenary_tests.move`

- [ ] **Step 1: Write test file**

```move
#[test_only]
module pvp_bounty::mercenary_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use pvp_bounty::mercenary;

const COMMANDER: address = @0xA;
const BATTLE_JUDGE: address = @0xB;
const MERC1: address = @0xC;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;

#[test]
fun test_pvp_happy_path() {
    let mut scenario = ts::begin(COMMANDER);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. Commander issues kill order (reward=1000, stake=100 i.e. 10%)
    ts::next_tx(&mut scenario, COMMANDER);
    // Total escrow = 1000 * 3 mercs = 3000
    let payment = coin::mint_for_testing<SUI>(3000, ts::ctx(&mut scenario));
    let change = mercenary::issue_kill_order(
        b"Kill Order: Pirate Lord Zephyr".to_string(),
        b"Eliminate target in Sector K-9".to_string(),
        payment,
        1000,
        DEADLINE,
        BATTLE_JUDGE,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // 2. Mercenary accepts (needs 100 stake = 1000 * 10%)
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(mercenary::kill_order_stake(&bounty) == 100);

    let stake_coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    let (ticket, stake_change) = mercenary::accept_kill_order(
        &mut bounty, stake_coin, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(stake_change);
    transfer::transfer(ticket, MERC1);
    ts::return_shared(bounty);

    // 3. Battle Judge verifies the kill
    ts::next_tx(&mut scenario, BATTLE_JUDGE);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    mercenary::verify_kill(&mut bounty, MERC1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Mercenary collects bounty
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    mercenary::collect_bounty(&mut bounty, ticket, ts::ctx(&mut scenario));

    // Verify: 2000 escrow left (2 remaining merc slots), stake pool drained for merc1
    assert!(bounty::escrow_value(&bounty) == 2000);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_pvp_abandon() {
    let mut scenario = ts::begin(COMMANDER);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // Commander issues kill order
    ts::next_tx(&mut scenario, COMMANDER);
    let payment = coin::mint_for_testing<SUI>(3000, ts::ctx(&mut scenario));
    let change = mercenary::issue_kill_order(
        b"Kill Order: Rogue Captain".to_string(),
        b"Eliminate target".to_string(),
        payment,
        1000,
        DEADLINE,
        BATTLE_JUDGE,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Mercenary accepts
    ts::next_tx(&mut scenario, MERC1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake_coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    let (ticket, stake_change) = mercenary::accept_kill_order(
        &mut bounty, stake_coin, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(stake_change);

    // Mercenary deserts — stake forfeited to commander
    mercenary::desert(&mut bounty, ticket, &clock, ts::ctx(&mut scenario));

    // Verify: stake pool drained (forfeited to commander), status back to open
    assert!(mercenary::kill_order_status(&bounty) == constants::status_open());
    assert!(bounty::active_claims(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

- [ ] **Step 2: Run tests**

Run: `cd examples/pvp_bounty && sui move test`
Expected: 2 tests passed

- [ ] **Step 3: Commit**

```bash
git add examples/pvp_bounty/sources/tests/mercenary_tests.move
git commit -m "test(examples): pvp bounty — happy path + abandon (desertion) tests"
```

---

### Task 5: Logistics Bounty — Move.toml + Module

**Files:**
- Create: `examples/logistics_bounty/Move.toml`
- Create: `examples/logistics_bounty/sources/logistics.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "logistics_bounty"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }
# Local development (clone repo, then build + test)
BountyEscrow = { local = "../../bounty_escrow" }
# Production (testnet published package):
# BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }

[addresses]
logistics_bounty = "0x0"
```

- [ ] **Step 2: Create logistics.move**

```move
/// Logistics Bounty — Tribal Governance DAO integration example.
///
/// DAO posts logistics task → Runner accepts (security deposit) →
/// DAO Council verifies → Runner collects payment.
/// Also demonstrates cancel → withdrawal pattern (cancel + withdraw_penalty
/// + withdraw_remaining).
///
/// TypeScript PTB examples: see docs/integration-guide.md §6
module logistics_bounty::logistics;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;

// ═══════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════

const MAX_RUNNERS: u64 = 1;                // single runner per task
const GRACE_PERIOD_MS: u64 = 259_200_000;  // 3 days
const CLEANUP_REWARD_BPS: u16 = 50;         // 0.5%

// ═══════════════════════════════════════════════
// DAO (creator) functions
// ═══════════════════════════════════════════════

/// DAO posts a logistics task.
/// `security_deposit`: runner must stake this amount as guarantee.
/// `dao_multisig`: the multi-sig address that also acts as verifier.
/// Returns change coin (composable).
public fun post_logistics_task(
    title: String,
    description: String,
    treasury_coin: Coin<SUI>,
    reward: u64,
    security_deposit: u64,
    deadline: u64,
    dao_multisig: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    bounty::create_bounty<SUI>(
        title,
        description,
        treasury_coin,
        reward,
        security_deposit,
        MAX_RUNNERS,
        deadline,
        GRACE_PERIOD_MS,
        CLEANUP_REWARD_BPS,
        dao_multisig,
        clock,
        ctx,
    )
}

/// DAO cancels the task. If a runner has claimed, triggers withdrawal pattern.
public fun cancel_task(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::cancel_bounty<SUI>(bounty, ctx)
}

/// After all runners have withdrawn penalties, DAO takes remaining funds.
public fun dao_withdraw_remaining(
    bounty: &mut Bounty<SUI>,
    ctx: &mut TxContext,
) {
    bounty::withdraw_remaining_bounty<SUI>(bounty, ctx)
}

// ═══════════════════════════════════════════════
// Runner (hunter) functions
// ═══════════════════════════════════════════════

/// Runner accepts the logistics task with security deposit.
/// Returns (ClaimTicket, change coin).
public fun accept_logistics_task(
    bounty: &mut Bounty<SUI>,
    deposit_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, deposit_coin, clock, ctx)
}

/// Runner collects payment after DAO council approval.
public fun collect_payment(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::claim_reward_bounty<SUI>(bounty, ticket, ctx)
}

/// After DAO cancels, runner withdraws deposit + penalty compensation.
public fun runner_withdraw(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    bounty::withdraw_penalty_bounty<SUI>(bounty, ticket, ctx)
}

// ═══════════════════════════════════════════════
// DAO Council (verifier) functions
// ═══════════════════════════════════════════════

/// DAO Council approves delivery.
/// In production, verify delivery proof before approving.
public fun approve_delivery(
    bounty: &mut Bounty<SUI>,
    runner: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::approve_hunter<SUI>(bounty, runner, cap, clock, ctx)
}

// ═══════════════════════════════════════════════
// Read-only accessors
// ═══════════════════════════════════════════════

public fun task_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun task_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}
```

- [ ] **Step 3: Build**

Run: `cd examples/logistics_bounty && sui move build`
Expected: success

- [ ] **Step 4: Commit**

```bash
git add examples/logistics_bounty/Move.toml examples/logistics_bounty/sources/logistics.move
git commit -m "feat(examples): logistics bounty wrapper — DAO task + security deposit scenario"
```

---

### Task 6: Logistics Bounty — Tests

**Files:**
- Create: `examples/logistics_bounty/sources/tests/logistics_tests.move`

- [ ] **Step 1: Write test file**

```move
#[test_only]
module logistics_bounty::logistics_tests;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;
use logistics_bounty::logistics;

const DAO: address = @0xA;          // creator + verifier (multi-sig)
const RUNNER: address = @0xC;

const BASE_TIME: u64 = 1_000_000_000;
const DEADLINE: u64 = 1_000_000_000 + 86_400_000;

#[test]
fun test_logistics_happy_path() {
    let mut scenario = ts::begin(DAO);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // 1. DAO posts logistics task (reward=2000, deposit=500)
    ts::next_tx(&mut scenario, DAO);
    let treasury = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    let change = logistics::post_logistics_task(
        b"Supply Run: Outpost Gamma".to_string(),
        b"Deliver 500 fuel cells".to_string(),
        treasury,
        2000,       // reward
        500,        // security deposit
        DEADLINE,
        DAO,        // DAO is also verifier
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // 2. Runner accepts with deposit
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let deposit = coin::mint_for_testing<SUI>(500, ts::ctx(&mut scenario));
    let (ticket, dep_change) = logistics::accept_logistics_task(
        &mut bounty, deposit, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(dep_change);

    assert!(logistics::task_status(&bounty) == constants::status_claimed());
    assert!(bounty::stake_pool_value(&bounty) == 500);

    transfer::transfer(ticket, RUNNER);
    ts::return_shared(bounty);

    // 3. DAO approves delivery
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    logistics::approve_delivery(&mut bounty, RUNNER, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // 4. Runner collects payment
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    logistics::collect_payment(&mut bounty, ticket, ts::ctx(&mut scenario));

    assert!(logistics::task_status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_logistics_cancel_withdraw() {
    let mut scenario = ts::begin(DAO);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, BASE_TIME);

    // DAO posts task
    ts::next_tx(&mut scenario, DAO);
    let treasury = coin::mint_for_testing<SUI>(2000, ts::ctx(&mut scenario));
    let change = logistics::post_logistics_task(
        b"Repair: Station Delta".to_string(),
        b"Fix hull breach".to_string(),
        treasury,
        2000,
        500,
        DEADLINE,
        DAO,
        &clock,
        ts::ctx(&mut scenario),
    );
    coin::destroy_zero(change);

    // Runner accepts
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let deposit = coin::mint_for_testing<SUI>(500, ts::ctx(&mut scenario));
    let (ticket, dep_change) = logistics::accept_logistics_task(
        &mut bounty, deposit, &clock, ts::ctx(&mut scenario),
    );
    coin::destroy_zero(dep_change);
    transfer::transfer(ticket, RUNNER);
    ts::return_shared(bounty);

    // DAO cancels task (runner has claimed → withdrawal pattern)
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    logistics::cancel_task(&mut bounty, ts::ctx(&mut scenario));
    assert!(logistics::task_status(&bounty) == constants::status_cancelled());
    ts::return_shared(bounty);

    // Runner withdraws deposit + penalty compensation
    ts::next_tx(&mut scenario, RUNNER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    logistics::runner_withdraw(&mut bounty, ticket, ts::ctx(&mut scenario));
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    // DAO withdraws remaining
    ts::next_tx(&mut scenario, DAO);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    logistics::dao_withdraw_remaining(&mut bounty, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

- [ ] **Step 2: Run tests**

Run: `cd examples/logistics_bounty && sui move test`
Expected: 2 tests passed

- [ ] **Step 3: Commit**

```bash
git add examples/logistics_bounty/sources/tests/logistics_tests.move
git commit -m "test(examples): logistics bounty — happy path + cancel withdrawal tests"
```

---

### Task 7: README.md

**Files:**
- Create: `examples/README.md`

- [ ] **Step 1: Create README**

```markdown
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
# BountyEscrow = { local = "../../bounty_escrow" }
BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }
```

> **Note:** Published address only supports `sui move build`, not `sui move test` (tests need local source).

## What Each Example Covers

**Intel Bounty** — Happy path + expire (cleanup reward)
**PvP Bounty** — Happy path + abandon (desertion / stake forfeiture)
**Logistics Bounty** — Happy path + cancel → withdrawal pattern (penalty + remaining)

Together, the three examples cover every public API in the protocol.

## Generic Coin Type

All examples use `Coin<SUI>` for simplicity. The protocol supports any coin type via `Bounty<T>` — replace `SUI` with your custom coin type.

## TypeScript PTB Examples

See the [Integration Guide](../docs/integration-guide.md):
- §4 — Intel Bounty PTB flow
- §5 — PvP Bounty PTB flow
- §6 — Logistics Bounty PTB flow
- §7 — Events & Indexing
```

- [ ] **Step 2: Commit**

```bash
git add examples/README.md
git commit -m "docs(examples): README — quick start, dependency switching, scenario overview"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Build all three packages**

```bash
cd examples/intel_bounty && sui move build && \
cd ../pvp_bounty && sui move build && \
cd ../logistics_bounty && sui move build
```

Expected: all 3 build successfully

- [ ] **Step 2: Test all three packages**

```bash
cd examples/intel_bounty && sui move test && \
cd ../pvp_bounty && sui move test && \
cd ../logistics_bounty && sui move test
```

Expected: 6 tests total (2 + 2 + 2), all passing

- [ ] **Step 3: Squash commit if needed, or leave as-is**

Review the git log. If clean, done. If any fixups were needed during tasks, create a final cleanup commit.
