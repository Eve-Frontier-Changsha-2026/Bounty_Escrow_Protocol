# Bounty Escrow Protocol — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Additionally, use `sui-developer` skill for Move code generation quality checks, and `sui-tester` skill for test execution with gas tracking.

**Goal:** Implement a Sui Move smart contract protocol for trustless bounty creation, escrow, staking, verification, and payout — serving as composable infrastructure for the EVE Frontier ecosystem.

**Architecture:** Four Move modules (`constants`, `escrow`, `verifier`, `bounty`) + one init module (`display`). `bounty.move` is the entry point containing all public/entry functions and the state machine. `escrow.move` and `verifier.move` are package-internal helpers. Two-step verification (approve → claim_reward), withdrawal pattern for cancel, grace period for post-deadline verification.

**Tech Stack:** Sui Move (2024 edition), Sui CLI, `sui move test`, `sui move build`

**Spec:** `docs/superpowers/specs/2026-03-20-bounty-escrow-protocol-design.md`
**Red Team Report:** `docs/superpowers/specs/2026-03-20-red-team-report.md`

---

## File Structure

```
bounty_escrow/
├── Move.toml
├── sources/
│   ├── constants.move       ← 狀態碼、上限、錯誤碼（純常數，無邏輯）
│   ├── escrow.move          ← Balance 操作：lock, release, calculate（package-internal）
│   ├── verifier.move        ← VerifierCap CRUD + 驗證（package-internal）
│   ├── bounty.move          ← 核心：struct 定義 + 狀態機 + entry/public fun
│   └── display.move         ← Publisher claim + Display V2 registration
└── tests/
    ├── test_create.move
    ├── test_claim.move
    ├── test_approve_claim.move
    ├── test_cancel_withdraw.move
    ├── test_expire.move
    ├── test_abandon.move
    └── test_monkey.move
```

**責任分離**：
- `constants.move`：所有模組共用的常數。改動頻率最低。
- `escrow.move`：只處理 `Balance<T>` 的數學和轉帳，不知道 Bounty 是什麼。
- `verifier.move`：只處理 `VerifierCap` 的 mint/validate，不知道 Bounty 狀態。
- `bounty.move`：唯一知道完整業務邏輯的模組，呼叫 escrow 和 verifier。
- `display.move`：一次性 init，部署後不再觸碰。

## Implementation Rules

### public fun + entry fun 雙版本（所有 entry function 必須遵守）

每個 entry function 都必須有對應的 `public fun` 版本。模式：

```move
// public fun: 回傳值，不做 transfer，供上層合約組合呼叫
public fun do_something_bounty<T>(...) : ReturnType { ... }

// entry fun: 呼叫 public fun，做 implicit transfer，供 CLI/wallet 使用
public entry fun do_something<T>(...) {
    let result = do_something_bounty(...);
    transfer::public_transfer(result, sender);
}
```

若函式不產生新物件（如 `approve`, `abandon`, `expire`），`public fun` 版本直接執行邏輯即可，entry 版本只是 wrapper。

### cancel() 不需要 clock 參數

`cancel` 不涉及時間檢查，移除 `clock: &Clock` 參數。

### OTW 命名

`display.move` 的 OTW 使用 `DISPLAY`（匹配 module 名稱 `display`）。Spec 裡的 `BOUNTY_ESCROW` 是錯的（那需要 module 名也叫 `bounty_escrow`），以 plan 為準。

### withdraw_remaining 額外檢查

除了 `active_claims == 0`，也檢查 `vec_map::is_empty(&bounty.active_hunter_stakes)`。

---

## Task 1: Project Scaffold

**Files:**
- Create: `bounty_escrow/Move.toml`
- Create: `bounty_escrow/sources/constants.move`

- [ ] **Step 1: Create Move.toml**

```toml
[package]
name = "bounty_escrow"
edition = "2024"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }

[addresses]
bounty_escrow = "0x0"
```

- [ ] **Step 2: Create constants.move with all constants and error codes**

```move
module bounty_escrow::constants;

// === 狀態碼 ===
public fun status_open(): u8 { 0 }
public fun status_claimed(): u8 { 1 }
public fun status_completed(): u8 { 2 }
public fun status_cancelled(): u8 { 3 }
public fun status_expired(): u8 { 4 }

// === 上限 ===
public fun max_cleanup_reward_bps(): u16 { 1000 }
public fun max_claims(): u64 { 100 }
public fun max_title_length(): u64 { 256 }
public fun max_description_length(): u64 { 2048 }
public fun max_metadata_entries(): u64 { 20 }
public fun max_metadata_value_length(): u64 { 1024 }
public fun min_deadline_duration(): u64 { 3_600_000 }
public fun max_deadline_duration(): u64 { 31_536_000_000 }
public fun default_grace_period(): u64 { 86_400_000 }
public fun current_version(): u64 { 1 }

// === 錯誤碼 ===
public fun e_insufficient_escrow(): u64 { 0 }
public fun e_deadline_too_soon(): u64 { 1 }
public fun e_deadline_too_far(): u64 { 2 }
public fun e_cleanup_bps_too_high(): u64 { 3 }
public fun e_title_too_long(): u64 { 4 }
public fun e_title_empty(): u64 { 5 }
public fun e_description_too_long(): u64 { 6 }
public fun e_bounty_not_open(): u64 { 7 }
public fun e_max_claims_reached(): u64 { 8 }
public fun e_insufficient_stake(): u64 { 9 }
public fun e_deadline_passed(): u64 { 10 }
public fun e_creator_cannot_claim(): u64 { 11 }
public fun e_already_claimed(): u64 { 12 }
public fun e_not_creator(): u64 { 13 }
public fun e_bounty_not_cancellable(): u64 { 14 }
public fun e_insufficient_escrow_for_penalty(): u64 { 15 }
public fun e_invalid_verifier_cap(): u64 { 16 }
public fun e_hunter_not_active(): u64 { 17 }
public fun e_insufficient_escrow_for_reward(): u64 { 18 }
public fun e_not_ticket_owner(): u64 { 19 }
public fun e_grace_period_not_passed(): u64 { 20 }
public fun e_bounty_not_active(): u64 { 21 }
public fun e_max_claims_zero(): u64 { 22 }
public fun e_reward_amount_zero(): u64 { 23 }
public fun e_max_claims_too_high(): u64 { 24 }
public fun e_bounty_not_terminal(): u64 { 25 }
public fun e_ticket_bounty_mismatch(): u64 { 26 }
public fun e_hunter_not_approved(): u64 { 27 }
public fun e_bounty_not_cancelled(): u64 { 28 }
public fun e_hunters_not_withdrawn(): u64 { 29 }
public fun e_abandon_after_deadline(): u64 { 30 }
public fun e_too_many_metadata(): u64 { 31 }
public fun e_metadata_value_too_long(): u64 { 32 }
public fun e_already_approved(): u64 { 33 }
public fun e_overflow(): u64 { 34 }
```

- [ ] **Step 3: Verify build**

Run: `cd bounty_escrow && sui move build`
Expected: Build Successful

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/Move.toml bounty_escrow/sources/constants.move
git commit -m "feat(bounty): scaffold project + constants module"
```

---

## Task 2: Escrow Module

**Files:**
- Create: `bounty_escrow/sources/escrow.move`
- Create: `bounty_escrow/tests/test_escrow.move` (internal helper test, optional)

- [ ] **Step 1: Implement escrow.move**

```move
module bounty_escrow::escrow;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::tx_context::TxContext;
use sui::transfer;

/// Lock `amount` from `coin` into `balance`. Returns change back as Coin.
public(package) fun lock<T>(
    bal: &mut Balance<T>,
    coin: Coin<T>,
    amount: u64,
    ctx: &mut TxContext,
): Coin<T> {
    let coin_bal = coin::into_balance(coin);
    let locked = balance::split(&mut coin_bal, amount);
    balance::join(bal, locked);
    coin::from_balance(coin_bal, ctx)
}

/// Release `amount` from `balance` and send as Coin to `recipient`.
public(package) fun release_to<T>(
    bal: &mut Balance<T>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = coin::take(bal, amount, ctx);
    transfer::public_transfer(coin, recipient);
}

/// Release entire balance to `recipient`.
public(package) fun release_all<T>(
    bal: &mut Balance<T>,
    recipient: address,
    ctx: &mut TxContext,
) {
    let amount = balance::value(bal);
    if (amount > 0) {
        release_to(bal, amount, recipient, ctx);
    };
}

/// Transfer `amount` from one balance to another.
public(package) fun transfer_between<T>(
    from: &mut Balance<T>,
    to: &mut Balance<T>,
    amount: u64,
) {
    let chunk = balance::split(from, amount);
    balance::join(to, chunk);
}

/// Calculate cleanup reward using u128 intermediate to prevent overflow.
/// Returns max(result, 1) when bps > 0 and total > 0, else 0.
public(package) fun calculate_cleanup_reward(total: u64, bps: u16): u64 {
    if (bps == 0 || total == 0) return 0;
    let result = ((total as u128) * (bps as u128) / 10000u128) as u64;
    if (result == 0) 1 else result
}
```

- [ ] **Step 2: Verify build**

Run: `sui move build`
Expected: Build Successful

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/sources/escrow.move
git commit -m "feat(bounty): escrow module — Balance lock/release/calculate"
```

---

## Task 3: Verifier Module

**Files:**
- Create: `bounty_escrow/sources/verifier.move`

- [ ] **Step 1: Implement verifier.move**

```move
module bounty_escrow::verifier;

use sui::object::{Self, UID, ID};
use sui::tx_context::TxContext;
use sui::transfer;
use bounty_escrow::constants;

/// Capability token for verifying bounty completion.
/// Only minted inside bounty::create via issue_cap.
public struct VerifierCap has key {
    id: UID,
    bounty_id: ID,
}

/// Mint a VerifierCap and transfer to `verifier` address.
public(package) fun issue_cap(
    bounty_id: ID,
    verifier: address,
    ctx: &mut TxContext,
) {
    let cap = VerifierCap {
        id: object::new(ctx),
        bounty_id,
    };
    transfer::transfer(cap, verifier);
}

/// Assert cap belongs to the given bounty.
public(package) fun validate_cap(cap: &VerifierCap, bounty_id: ID) {
    assert!(cap.bounty_id == bounty_id, constants::e_invalid_verifier_cap());
}

/// Return the bounty_id this cap is for.
public(package) fun bounty_id(cap: &VerifierCap): ID {
    cap.bounty_id
}

/// Return the cap's ID (for events).
public(package) fun cap_id(cap: &VerifierCap): ID {
    object::id(cap)
}

/// Destroy a VerifierCap. Caller must verify bounty is in terminal state before calling.
public(package) fun destroy_cap(cap: VerifierCap) {
    let VerifierCap { id, bounty_id: _ } = cap;
    object::delete(id);
}
```

- [ ] **Step 2: Verify build**

Run: `sui move build`
Expected: Build Successful

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/sources/verifier.move
git commit -m "feat(bounty): verifier module — VerifierCap CRUD"
```

---

## Task 4: Bounty Structs + Create

**Files:**
- Create: `bounty_escrow/sources/bounty.move`
- Create: `bounty_escrow/tests/test_create.move`

This is the largest task — defines all structs, events, and the `create` function.

- [ ] **Step 1: Define all structs and events in bounty.move**

```move
module bounty_escrow::bounty;

use std::string::String;
use sui::object::{Self, UID, ID};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::clock::Clock;
use sui::tx_context::TxContext;
use sui::transfer;
use sui::event;
use sui::vec_set::{Self, VecSet};
use sui::vec_map::{Self, VecMap};
use sui::types;
use bounty_escrow::constants;
use bounty_escrow::escrow;
use bounty_escrow::verifier::{Self, VerifierCap};

// === Structs ===

public struct Bounty<phantom T> has key {
    id: UID,
    version: u64,
    creator: address,
    title: String,
    description: String,
    escrow: Balance<T>,
    stake_pool: Balance<T>,
    reward_amount: u64,
    required_stake: u64,
    cleanup_reward_bps: u16,
    deadline: u64,
    grace_period: u64,
    status: u8,
    max_claims: u64,
    active_claims: u64,
    completed_claims: u64,
    claimed_hunters: VecSet<address>,
    active_hunter_stakes: VecMap<address, u64>,
    approved_hunters: VecSet<address>,
    metadata: VecMap<String, String>,
}

public struct ClaimTicket has key {
    id: UID,
    bounty_id: ID,
    hunter: address,
    stake_amount: u64,
    claimed_at: u64,
}

// === Events ===

public struct BountyCreated has copy, drop {
    bounty_id: ID,
    creator: address,
    coin_type: String,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    verifier: address,
}

public struct BountyClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    stake_amount: u64,
}

public struct BountyApproved has copy, drop {
    bounty_id: ID,
    hunter: address,
    verifier: address,
}

public struct RewardClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    reward_amount: u64,
    stake_returned: u64,
}

public struct BountyCancelled has copy, drop {
    bounty_id: ID,
    creator: address,
    active_claims_at_cancel: u64,
    penalty_per_hunter: u64,
}

public struct PenaltyWithdrawn has copy, drop {
    bounty_id: ID,
    hunter: address,
    stake_returned: u64,
    penalty_received: u64,
}

public struct RemainingWithdrawn has copy, drop {
    bounty_id: ID,
    creator: address,
    escrow_returned: u64,
    stakes_returned: u64,
}

public struct BountyExpired has copy, drop {
    bounty_id: ID,
    caller: address,
    cleanup_reward: u64,
    refund_to_creator: u64,
    forfeited_stakes: u64,
}

public struct BountyAbandoned has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    forfeited_stake: u64,
}

public struct TicketDestroyed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
}

public struct VerifierCapDestroyed has copy, drop {
    bounty_id: ID,
    cap_id: ID,
}
```

- [ ] **Step 2: Implement `create` public fun + entry fun**

Add to `bounty.move`:

```move
// === Accessors (for tests and upper-layer reads) ===

public fun status<T>(bounty: &Bounty<T>): u8 { bounty.status }
public fun creator<T>(bounty: &Bounty<T>): address { bounty.creator }
public fun reward_amount<T>(bounty: &Bounty<T>): u64 { bounty.reward_amount }
public fun required_stake<T>(bounty: &Bounty<T>): u64 { bounty.required_stake }
public fun active_claims<T>(bounty: &Bounty<T>): u64 { bounty.active_claims }
public fun completed_claims<T>(bounty: &Bounty<T>): u64 { bounty.completed_claims }
public fun max_claims<T>(bounty: &Bounty<T>): u64 { bounty.max_claims }
public fun deadline<T>(bounty: &Bounty<T>): u64 { bounty.deadline }
public fun grace_period<T>(bounty: &Bounty<T>): u64 { bounty.grace_period }
public fun escrow_value<T>(bounty: &Bounty<T>): u64 { balance::value(&bounty.escrow) }
public fun stake_pool_value<T>(bounty: &Bounty<T>): u64 { balance::value(&bounty.stake_pool) }
public fun ticket_bounty_id(ticket: &ClaimTicket): ID { ticket.bounty_id }
public fun ticket_hunter(ticket: &ClaimTicket): address { ticket.hunter }
public fun ticket_stake_amount(ticket: &ClaimTicket): u64 { ticket.stake_amount }

// === Helper: checked multiply ===

fun checked_mul(a: u64, b: u64): u64 {
    let result = (a as u128) * (b as u128);
    assert!(result <= (18_446_744_073_709_551_615u128), constants::e_overflow());
    result as u64
}

// === Helper: is terminal state ===

fun is_terminal(status: u8): bool {
    status == constants::status_completed() ||
    status == constants::status_cancelled() ||
    status == constants::status_expired()
}

// === Create ===

/// Create a new bounty. Returns (shared Bounty, VerifierCap sent to verifier).
public fun create_bounty<T>(
    title: String,
    description: String,
    mut coin: Coin<T>,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    cleanup_reward_bps: u16,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T> {
    let now = sui::clock::timestamp_ms(clock);
    let sender = tx_context::sender(ctx);

    // --- Validations ---
    assert!(title.length() > 0, constants::e_title_empty());
    assert!(title.length() <= constants::max_title_length(), constants::e_title_too_long());
    assert!(description.length() <= constants::max_description_length(), constants::e_description_too_long());
    assert!(reward_amount > 0, constants::e_reward_amount_zero());
    assert!(max_claims > 0, constants::e_max_claims_zero());
    assert!(max_claims <= constants::max_claims(), constants::e_max_claims_too_high());
    assert!(cleanup_reward_bps <= constants::max_cleanup_reward_bps(), constants::e_cleanup_bps_too_high());
    assert!(deadline >= now + constants::min_deadline_duration(), constants::e_deadline_too_soon());
    assert!(deadline <= now + constants::max_deadline_duration(), constants::e_deadline_too_far());

    let total_escrow = checked_mul(reward_amount, max_claims);
    assert!(coin::value(&coin) >= total_escrow, constants::e_insufficient_escrow());

    // --- Lock funds ---
    let mut escrow_bal = balance::zero<T>();
    let change = escrow::lock(&mut escrow_bal, coin, total_escrow, ctx);

    // --- Build Bounty ---
    let mut bounty = Bounty<T> {
        id: object::new(ctx),
        version: constants::current_version(),
        creator: sender,
        title,
        description,
        escrow: escrow_bal,
        stake_pool: balance::zero(),
        reward_amount,
        required_stake,
        cleanup_reward_bps,
        deadline,
        grace_period,
        status: constants::status_open(),
        max_claims,
        active_claims: 0,
        completed_claims: 0,
        claimed_hunters: vec_set::empty(),
        active_hunter_stakes: vec_map::empty(),
        approved_hunters: vec_set::empty(),
        metadata: vec_map::empty(),
    };

    let bounty_id = object::id(&bounty);

    // --- Mint VerifierCap ---
    verifier::issue_cap(bounty_id, verifier_addr, ctx);

    // --- Emit event ---
    event::emit(BountyCreated {
        bounty_id,
        creator: sender,
        coin_type: std::type_name::into_string(std::type_name::get<T>()),
        reward_amount,
        required_stake,
        max_claims,
        deadline,
        grace_period,
        verifier: verifier_addr,
    });

    // --- Share bounty ---
    transfer::share_object(bounty);

    change
}

/// Entry version: auto-transfers change back to sender.
public entry fun create<T>(
    title: String,
    description: String,
    coin: Coin<T>,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    cleanup_reward_bps: u16,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let change = create_bounty(
        title, description, coin,
        reward_amount, required_stake, max_claims,
        deadline, grace_period, cleanup_reward_bps,
        verifier_addr, clock, ctx,
    );
    let sender = tx_context::sender(ctx);
    if (coin::value(&change) > 0) {
        transfer::public_transfer(change, sender);
    } else {
        coin::destroy_zero(change);
    };
}
```

- [ ] **Step 3: Write test_create.move**

```move
#[test_only]
module bounty_escrow::test_create;

use sui::test_scenario::{Self as ts, Scenario};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

fun setup(scenario: &mut Scenario): Clock {
    let clock = clock::create_for_testing(ts::ctx(scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000); // 1B ms
    clock
}

#[test]
fun test_create_success() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);

    // create with 1000 reward, 100 stake, 5 max_claims
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    let deadline = 1_000_000_000 + 86_400_000; // +24h
    bounty::create<SUI>(
        b"Kill pirate".to_string(),
        b"Destroy pirate ship in sector 7".to_string(),
        coin, 1000, 100, 5,
        deadline, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // verify bounty exists
    ts::next_tx(&mut scenario, CREATOR);
    let bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    assert!(bounty::status(&bounty) == constants::status_open());
    assert!(bounty::reward_amount(&bounty) == 1000);
    assert!(bounty::required_stake(&bounty) == 100);
    assert!(bounty::max_claims(&bounty) == 5);
    assert!(bounty::escrow_value(&bounty) == 5000);
    assert!(bounty::active_claims(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_title_empty)]
fun test_create_empty_title() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_deadline_too_soon)]
fun test_create_deadline_too_soon() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 1000, 86_400_000, 100, // only 1s ahead
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_insufficient_escrow)]
fun test_create_insufficient_escrow() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario)); // need 5000
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_max_claims_too_high)]
fun test_create_max_claims_too_high() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(101_000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 101, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_reward_amount_zero)]
fun test_create_zero_reward() {
    let mut scenario = ts::begin(CREATOR);
    let clock = setup(&mut scenario);
    let coin = coin::mint_for_testing<SUI>(5000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        0, 100, 5, 1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

Also add these test functions:
- `test_create_deadline_too_far` — deadline > now + MAX_DEADLINE_DURATION → aborts `E_DEADLINE_TOO_FAR`
- `test_create_description_too_long` — description > 2048 chars → aborts `E_DESCRIPTION_TOO_LONG`
- `test_create_bps_too_high` — cleanup_reward_bps = 1001 → aborts `E_CLEANUP_BPS_TOO_HIGH`
- `test_create_change_returned` — coin = 6000, need 5000 → verify 1000 change returned

- [ ] **Step 4: Run tests**

Run: `sui move test --filter test_create`
Expected: ALL PASS (9 tests)

- [ ] **Step 5: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_create.move
git commit -m "feat(bounty): Bounty structs + create function + tests"
```

---

## Task 5: Claim

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `claim` + `claim_bounty`)
- Create: `bounty_escrow/tests/test_claim.move`

- [ ] **Step 1: Implement claim in bounty.move**

```move
// === Claim ===

/// Hunter claims a bounty, staking required_stake.
public fun claim_bounty<T>(
    bounty: &mut Bounty<T>,
    mut stake_coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<T>) {
    let now = sui::clock::timestamp_ms(clock);
    let hunter = tx_context::sender(ctx);

    assert!(bounty.status == constants::status_open(), constants::e_bounty_not_open());
    assert!(bounty.active_claims < bounty.max_claims, constants::e_max_claims_reached());
    assert!(now < bounty.deadline, constants::e_deadline_passed());
    assert!(hunter != bounty.creator, constants::e_creator_cannot_claim());
    assert!(!vec_set::contains(&bounty.claimed_hunters, &hunter), constants::e_already_claimed());
    assert!(coin::value(&stake_coin) >= bounty.required_stake, constants::e_insufficient_stake());

    // Lock stake
    let change = if (bounty.required_stake > 0) {
        escrow::lock(&mut bounty.stake_pool, stake_coin, bounty.required_stake, ctx)
    } else {
        stake_coin // no stake needed, return full coin as change
    };

    // Update state
    vec_set::insert(&mut bounty.claimed_hunters, hunter);
    vec_map::insert(&mut bounty.active_hunter_stakes, hunter, bounty.required_stake);
    bounty.active_claims = bounty.active_claims + 1;

    // Status transition
    if (bounty.active_claims == bounty.max_claims) {
        bounty.status = constants::status_claimed();
    };

    // Mint ticket
    let ticket = ClaimTicket {
        id: object::new(ctx),
        bounty_id: object::id(bounty),
        hunter,
        stake_amount: bounty.required_stake,
        claimed_at: now,
    };

    event::emit(BountyClaimed {
        bounty_id: object::id(bounty),
        ticket_id: object::id(&ticket),
        hunter,
        stake_amount: bounty.required_stake,
    });

    (ticket, change)
}

/// Entry version.
public entry fun claim<T>(
    bounty: &mut Bounty<T>,
    stake_coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let (ticket, change) = claim_bounty(bounty, stake_coin, clock, ctx);
    let sender = tx_context::sender(ctx);
    transfer::transfer(ticket, sender);
    if (coin::value(&change) > 0) {
        transfer::public_transfer(change, sender);
    } else {
        coin::destroy_zero(change);
    };
}
```

- [ ] **Step 2: Write test_claim.move**

Tests: normal claim, stake insufficient, duplicate claim, max claims reached, creator self-claim, deadline passed, claim triggers Open→Claimed.

```move
#[test_only]
module bounty_escrow::test_claim;

use sui::test_scenario::{Self as ts, Scenario};
use sui::clock::{Self, Clock};
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;
const HUNTER2: address = @0xD;

fun create_test_bounty(scenario: &mut Scenario, clock: &Clock, max_claims: u64) {
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(max_claims * 1000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Test bounty".to_string(), b"desc".to_string(), coin,
        1000, 100, max_claims,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
}

#[test]
fun test_claim_success() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_test_bounty(&mut scenario, &clock, 5);

    // Hunter1 claims
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    assert!(bounty::active_claims(&bounty) == 1);
    assert!(bounty::status(&bounty) == constants::status_open()); // still open (1/5)
    assert!(bounty::stake_pool_value(&bounty) == 100);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_claim_triggers_claimed_status() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_test_bounty(&mut scenario, &clock, 1); // max_claims = 1

    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    assert!(bounty::status(&bounty) == constants::status_claimed()); // 1/1 = Claimed
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_already_claimed)]
fun test_claim_duplicate() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_test_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    // same hunter tries again
    let stake2 = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake2, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_creator_cannot_claim)]
fun test_creator_cannot_claim_own() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    create_test_bounty(&mut scenario, &clock, 5);

    ts::next_tx(&mut scenario, CREATOR);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

Also add these test functions:
- `test_claim_deadline_passed` — advance clock past deadline → claim aborts `E_DEADLINE_PASSED`
- `test_claim_max_claims_reached` — create(max=1) → HUNTER1 claims → HUNTER2 claims → aborts `E_MAX_CLAIMS_REACHED`
- `test_claim_insufficient_stake` — stake_coin < required_stake → aborts `E_INSUFFICIENT_STAKE`

- [ ] **Step 3: Run tests**

Run: `sui move test --filter test_claim`
Expected: ALL PASS (7 tests)

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_claim.move
git commit -m "feat(bounty): claim function + hunter staking + tests"
```

---

## Task 6: Approve + Claim Reward (Two-Step Verify)

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `approve`, `claim_reward`)
- Create: `bounty_escrow/tests/test_approve_claim.move`

- [ ] **Step 1: Implement approve + claim_reward in bounty.move**

```move
// === Approve (verifier marks hunter as verified) ===

/// Public fun version — no side effects beyond state mutation.
public fun approve_hunter<T>(
    bounty: &mut Bounty<T>,
    hunter: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // (same logic as entry version below)
}

public entry fun approve<T>(
    bounty: &mut Bounty<T>,
    hunter: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = sui::clock::timestamp_ms(clock);
    let bounty_id = object::id(bounty);

    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    verifier::validate_cap(cap, bounty_id);
    assert!(vec_map::contains(&bounty.active_hunter_stakes, &hunter), constants::e_hunter_not_active());
    assert!(!vec_set::contains(&bounty.approved_hunters, &hunter), constants::e_already_approved());
    assert!(now <= bounty.deadline + bounty.grace_period, constants::e_grace_period_not_passed());

    vec_set::insert(&mut bounty.approved_hunters, hunter);

    event::emit(BountyApproved {
        bounty_id,
        hunter,
        verifier: tx_context::sender(ctx),
    });
}

// === Claim Reward (approved hunter collects reward + stake) ===

/// Helper: resolve claim completion, update counters, check for Completed transition.
fun resolve_claim<T>(bounty: &mut Bounty<T>, hunter: address, is_completion: bool) {
    // Remove from active
    let (_, _stake) = vec_map::remove(&mut bounty.active_hunter_stakes, &hunter);
    bounty.active_claims = bounty.active_claims - 1;

    if (is_completion) {
        bounty.completed_claims = bounty.completed_claims + 1;
        // Remove from approved
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    // Check Completed transition
    if (bounty.active_claims == 0 && bounty.completed_claims > 0 &&
        vec_set::size(&bounty.approved_hunters) == 0) {
        bounty.status = constants::status_completed();
    } else if (bounty.active_claims < bounty.max_claims &&
               bounty.status == constants::status_claimed()) {
        bounty.status = constants::status_open();
    };
}

/// Public fun: returns (reward_coin, stake_coin) for upper-layer composition.
public fun claim_reward_bounty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
): (Coin<T>, Coin<T>) {
    // Same validation + logic, but return coins instead of transfer
    // ... (identical checks, then:)
    // let reward_coin = coin::take(&mut bounty.escrow, reward, ctx);
    // let stake_coin = coin::take(&mut bounty.stake_pool, stake_amount, ctx);
    // resolve_claim + event + destroy ticket
    // (reward_coin, stake_coin)
}

public entry fun claim_reward<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    let hunter = tx_context::sender(ctx);
    let bounty_id = object::id(bounty);

    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(vec_set::contains(&bounty.approved_hunters, &hunter), constants::e_hunter_not_approved());
    assert!(balance::value(&bounty.escrow) >= bounty.reward_amount, constants::e_insufficient_escrow_for_reward());

    let stake_amount = ticket.stake_amount;
    let reward = bounty.reward_amount;

    // Pay reward from escrow
    escrow::release_to(&mut bounty.escrow, reward, hunter, ctx);

    // Return stake from stake_pool
    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, hunter, ctx);
    };

    // Update state
    resolve_claim(bounty, hunter, true);

    event::emit(RewardClaimed {
        bounty_id,
        ticket_id: object::id(&ticket),
        hunter,
        reward_amount: reward,
        stake_returned: stake_amount,
    });

    // Destroy ticket
    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}
```

- [ ] **Step 2: Write test_approve_claim.move**

Tests: full approve→claim_reward flow, approve in grace period, approve after grace fails, double approve fails, claim_reward without approval fails, ticket mismatch, multi-hunter approve+claim→Completed.

```move
#[test_only]
module bounty_escrow::test_approve_claim;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::constants;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;
const HUNTER1: address = @0xC;

fun setup_claimed_bounty(scenario: &mut ts::Scenario, clock: &clock::Clock) {
    // Create
    ts::next_tx(scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(scenario));
    bounty::create<SUI>(
        b"Test".to_string(), b"desc".to_string(), coin,
        1000, 100, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, clock, ts::ctx(scenario),
    );
    // Claim
    ts::next_tx(scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(scenario);
    let stake = coin::mint_for_testing<SUI>(100, ts::ctx(scenario));
    bounty::claim<SUI>(&mut bounty, stake, clock, ts::ctx(scenario));
    ts::return_shared(bounty);
}

#[test]
fun test_approve_and_claim_reward() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    setup_claimed_bounty(&mut scenario, &clock);

    // Verifier approves
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Hunter claims reward
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    assert!(bounty::status(&bounty) == constants::status_completed());
    assert!(bounty::escrow_value(&bounty) == 0);
    assert!(bounty::stake_pool_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_approve_during_grace_period() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    setup_claimed_bounty(&mut scenario, &clock);

    // Advance past deadline but within grace period
    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 3_600_000); // deadline + 1hr

    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    // Should succeed — within grace period
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_grace_period_not_passed)]
fun test_approve_after_grace_period_fails() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    setup_claimed_bounty(&mut scenario, &clock);

    // Advance past deadline + grace
    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);

    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, HUNTER1, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = bounty_escrow::constants::e_hunter_not_approved)]
fun test_claim_reward_without_approval() {
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);
    setup_claimed_bounty(&mut scenario, &clock);

    // Hunter tries to claim without approve
    ts::next_tx(&mut scenario, HUNTER1);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));

    ts::return_shared(bounty);
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
```

- [ ] **Step 3: Run tests**

Run: `sui move test --filter test_approve`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_approve_claim.move
git commit -m "feat(bounty): two-step verify — approve + claim_reward + tests"
```

---

## Task 7: Abandon

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `abandon_bounty` public fun + `abandon` entry fun)
- Create: `bounty_escrow/tests/test_abandon.move`

**Note:** Follow the dual-version pattern. `abandon_bounty<T>(...)` is the public fun (no transfer), `abandon<T>(...)` is the entry wrapper.

- [ ] **Step 1: Implement abandon in bounty.move**

```move
// === Abandon ===

public entry fun abandon<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = sui::clock::timestamp_ms(clock);
    let hunter = tx_context::sender(ctx);
    let bounty_id = object::id(bounty);

    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    assert!(now < bounty.deadline, constants::e_abandon_after_deadline());

    let stake_amount = ticket.stake_amount;

    // Forfeit stake to creator
    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, bounty.creator, ctx);
    };

    // Remove from approved if was approved
    if (vec_set::contains(&bounty.approved_hunters, &hunter)) {
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    // Update state
    resolve_claim(bounty, hunter, false);

    event::emit(BountyAbandoned {
        bounty_id,
        ticket_id: object::id(&ticket),
        hunter,
        forfeited_stake: stake_amount,
    });

    // Destroy ticket
    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}
```

- [ ] **Step 2: Write test_abandon.move**

Must include these test functions:
- `test_abandon_success` — claim → abandon → stake_pool 減少，creator 收到 forfeited stake，active_claims -= 1
- `test_abandon_reopens_claimed` — create(max=1) → claim (status=Claimed) → abandon → status 回到 Open
- `test_abandon_after_deadline_fails` — advance clock past deadline → abandon aborts with `E_ABANDON_AFTER_DEADLINE`
- `test_abandon_non_owner_fails` — HUNTER2 tries to abandon HUNTER1's ticket → aborts with `E_NOT_TICKET_OWNER`
- `test_abandon_wrong_bounty_fails` — ticket from bounty A used on bounty B → aborts with `E_TICKET_BOUNTY_MISMATCH`

Use same helper pattern as test_claim (create_test_bounty + claim setup).

- [ ] **Step 3: Run tests**

Run: `sui move test --filter test_abandon`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_abandon.move
git commit -m "feat(bounty): abandon function — hunter forfeits stake + tests"
```

---

## Task 8: Cancel + Withdraw (Withdrawal Pattern)

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `cancel_bounty`/`cancel`, `withdraw_penalty_bounty`/`withdraw_penalty`, `withdraw_remaining_bounty`/`withdraw_remaining`)
- Create: `bounty_escrow/tests/test_cancel_withdraw.move`

**Note:** Each function follows the dual-version pattern. `cancel` 不需要 `clock` 參數。`withdraw_remaining` 額外檢查 `vec_map::is_empty(&bounty.active_hunter_stakes)`。

- [ ] **Step 1: Implement cancel + withdraw_penalty + withdraw_remaining**

```move
// === Cancel ===

public entry fun cancel<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == bounty.creator, constants::e_not_creator());
    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_cancellable());

    if (bounty.active_claims == 0) {
        // No active claims — direct refund
        escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);
        bounty.status = constants::status_cancelled();
        event::emit(BountyCancelled {
            bounty_id: object::id(bounty),
            creator: sender,
            active_claims_at_cancel: 0,
            penalty_per_hunter: 0,
        });
    } else {
        // Has active claims — verify escrow can cover penalties
        let total_penalty = checked_mul(bounty.required_stake, bounty.active_claims);
        assert!(balance::value(&bounty.escrow) >= total_penalty,
            constants::e_insufficient_escrow_for_penalty());

        bounty.status = constants::status_cancelled();
        event::emit(BountyCancelled {
            bounty_id: object::id(bounty),
            creator: sender,
            active_claims_at_cancel: bounty.active_claims,
            penalty_per_hunter: bounty.required_stake,
        });
        // Funds stay in bounty — hunters withdraw via withdraw_penalty()
    };
}

// === Withdraw Penalty (hunter pulls stake + penalty after cancel) ===

public entry fun withdraw_penalty<T>(
    bounty: &mut Bounty<T>,
    ticket: ClaimTicket,
    ctx: &mut TxContext,
) {
    let hunter = tx_context::sender(ctx);
    let bounty_id = object::id(bounty);

    assert!(bounty.status == constants::status_cancelled(), constants::e_bounty_not_cancelled());
    assert!(ticket.bounty_id == bounty_id, constants::e_ticket_bounty_mismatch());
    assert!(ticket.hunter == hunter, constants::e_not_ticket_owner());
    assert!(vec_map::contains(&bounty.active_hunter_stakes, &hunter), constants::e_hunter_not_active());

    let stake_amount = ticket.stake_amount;
    let penalty = bounty.required_stake;

    // Return stake from stake_pool
    if (stake_amount > 0) {
        escrow::release_to(&mut bounty.stake_pool, stake_amount, hunter, ctx);
    };

    // Pay penalty from escrow
    if (penalty > 0) {
        escrow::release_to(&mut bounty.escrow, penalty, hunter, ctx);
    };

    // Remove from active
    let (_, _) = vec_map::remove(&mut bounty.active_hunter_stakes, &hunter);
    bounty.active_claims = bounty.active_claims - 1;

    // Remove from approved if applicable
    if (vec_set::contains(&bounty.approved_hunters, &hunter)) {
        vec_set::remove(&mut bounty.approved_hunters, &hunter);
    };

    event::emit(PenaltyWithdrawn {
        bounty_id,
        hunter,
        stake_returned: stake_amount,
        penalty_received: penalty,
    });

    // Destroy ticket
    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);
}

// === Withdraw Remaining (creator pulls remaining after all hunters withdrew) ===

public entry fun withdraw_remaining<T>(
    bounty: &mut Bounty<T>,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == bounty.creator, constants::e_not_creator());
    assert!(bounty.status == constants::status_cancelled(), constants::e_bounty_not_cancelled());
    assert!(bounty.active_claims == 0, constants::e_hunters_not_withdrawn());
    assert!(vec_map::is_empty(&bounty.active_hunter_stakes), constants::e_hunters_not_withdrawn());

    let escrow_left = balance::value(&bounty.escrow);
    let stakes_left = balance::value(&bounty.stake_pool);

    escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);
    escrow::release_all(&mut bounty.stake_pool, bounty.creator, ctx);

    event::emit(RemainingWithdrawn {
        bounty_id: object::id(bounty),
        creator: sender,
        escrow_returned: escrow_left,
        stakes_returned: stakes_left,
    });
}
```

- [ ] **Step 2: Write test_cancel_withdraw.move**

Must include these test functions:
- `test_cancel_no_claims` — create → cancel → escrow 全額退回 creator，status = Cancelled
- `test_cancel_with_claims_full_flow` — create → claim → cancel → withdraw_penalty (hunter 拿 stake + penalty) → withdraw_remaining (creator 拿餘額)。驗證所有金額正確
- `test_cancel_non_creator_fails` — HUNTER tries cancel → aborts with `E_NOT_CREATOR`
- `test_cancel_insufficient_escrow_for_penalty` — create(stake=2000, reward=1000) → claim → approve + claim_reward (消耗部分 escrow) → cancel → aborts with `E_INSUFFICIENT_ESCROW_FOR_PENALTY`
- `test_withdraw_remaining_before_all_hunters_fails` — cancel with 2 active claims → 1 hunter withdraws → creator tries withdraw_remaining → aborts with `E_HUNTERS_NOT_WITHDRAWN`
- `test_double_cancel_fails` — cancel → cancel again → aborts with `E_BOUNTY_NOT_CANCELLABLE`
- `test_withdraw_penalty_not_cancelled_fails` — bounty still Open → hunter calls withdraw_penalty → aborts with `E_BOUNTY_NOT_CANCELLED`

- [ ] **Step 3: Run tests**

Run: `sui move test --filter test_cancel`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_cancel_withdraw.move
git commit -m "feat(bounty): cancel withdrawal pattern + penalty distribution + tests"
```

---

## Task 9: Expire

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `expire_bounty` public fun + `expire` entry fun)
- Create: `bounty_escrow/tests/test_expire.move`

**Note:** `expire_bounty<T>(...)` returns `Coin<T>` (cleanup reward) for upper-layer composition. `expire<T>(...)` entry version transfers cleanup reward to caller.

- [ ] **Step 1: Implement expire in bounty.move**

```move
// === Expire ===

public entry fun expire<T>(
    bounty: &mut Bounty<T>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let now = sui::clock::timestamp_ms(clock);
    let caller = tx_context::sender(ctx);

    assert!(bounty.status == constants::status_open() || bounty.status == constants::status_claimed(),
        constants::e_bounty_not_active());
    assert!(now > bounty.deadline + bounty.grace_period,
        constants::e_grace_period_not_passed());

    // Calculate cleanup reward
    let escrow_remaining = balance::value(&bounty.escrow);
    let cleanup_reward = escrow::calculate_cleanup_reward(escrow_remaining, bounty.cleanup_reward_bps);

    // Pay cleanup reward to caller
    if (cleanup_reward > 0) {
        escrow::release_to(&mut bounty.escrow, cleanup_reward, caller, ctx);
    };

    // Forfeit stakes to creator
    let forfeited = balance::value(&bounty.stake_pool);
    escrow::release_all(&mut bounty.stake_pool, bounty.creator, ctx);

    // Refund remaining escrow to creator
    let refund = balance::value(&bounty.escrow);
    escrow::release_all(&mut bounty.escrow, bounty.creator, ctx);

    bounty.status = constants::status_expired();

    // Clear active hunters (they lose stakes)
    while (vec_map::size(&bounty.active_hunter_stakes) > 0) {
        let (_, _) = vec_map::pop(&mut bounty.active_hunter_stakes);
    };
    bounty.active_claims = 0;

    event::emit(BountyExpired {
        bounty_id: object::id(bounty),
        caller,
        cleanup_reward,
        refund_to_creator: refund,
        forfeited_stakes: forfeited,
    });
}
```

- [ ] **Step 2: Write test_expire.move**

Must include these test functions:
- `test_expire_no_claims` — create → advance past deadline+grace → expire → cleanup_reward 給 caller，餘額退 creator
- `test_expire_with_claims_stakes_forfeited` — create → claim → advance past deadline+grace → expire → stake_pool 全額歸 creator，cleanup_reward 給 caller
- `test_expire_within_grace_period_fails` — advance to deadline + 1hr（在 grace 內）→ expire aborts with `E_GRACE_PERIOD_NOT_PASSED`
- `test_expire_after_grace_succeeds` — advance to deadline + grace + 1 → expire succeeds
- `test_expire_partial_verify` — create(max=3) → 3x claim → 1x approve+claim_reward → advance → expire → 驗證已 verify 的 hunter 不受影響，剩餘 2 hunter 的 stake 沒收
- `test_double_expire_fails` — expire → expire again → aborts with `E_BOUNTY_NOT_ACTIVE`

- [ ] **Step 3: Run tests**

Run: `sui move test --filter test_expire`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move bounty_escrow/tests/test_expire.move
git commit -m "feat(bounty): expire function — cleanup reward + stake forfeiture + tests"
```

---

## Task 10: Destroy Ticket + Destroy VerifierCap

**Files:**
- Modify: `bounty_escrow/sources/bounty.move` (add `destroy_ticket`, `destroy_verifier_cap`)

- [ ] **Step 1: Implement cleanup functions**

```move
// === Destroy Ticket (cleanup orphaned tickets after terminal state) ===

public entry fun destroy_ticket<T>(
    ticket: ClaimTicket,
    bounty: &Bounty<T>,
) {
    assert!(is_terminal(bounty.status), constants::e_bounty_not_terminal());
    assert!(ticket.bounty_id == object::id(bounty), constants::e_ticket_bounty_mismatch());

    let ticket_id = object::id(&ticket);
    let bounty_id = ticket.bounty_id;

    let ClaimTicket { id, bounty_id: _, hunter: _, stake_amount: _, claimed_at: _ } = ticket;
    object::delete(id);

    event::emit(TicketDestroyed { bounty_id, ticket_id });
}

// === Destroy VerifierCap ===

public entry fun destroy_verifier_cap<T>(
    cap: VerifierCap,
    bounty: &Bounty<T>,
) {
    assert!(is_terminal(bounty.status), constants::e_bounty_not_terminal());

    let bounty_id = verifier::bounty_id(&cap);
    assert!(bounty_id == object::id(bounty), constants::e_ticket_bounty_mismatch());

    let cap_id = verifier::cap_id(&cap);
    verifier::destroy_cap(cap);

    event::emit(VerifierCapDestroyed { bounty_id, cap_id });
}
```

- [ ] **Step 2: Add destroy tests to existing test files or create inline tests**

- [ ] **Step 3: Run all tests**

Run: `sui move test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add bounty_escrow/sources/bounty.move
git commit -m "feat(bounty): destroy_ticket + destroy_verifier_cap cleanup functions"
```

---

## Task 11: Display Module

**Files:**
- Create: `bounty_escrow/sources/display.move`

- [ ] **Step 1: Implement display.move**

```move
module bounty_escrow::display;

use sui::package;
use sui::tx_context::TxContext;
use sui::transfer;

/// OTW for claiming Publisher.
public struct DISPLAY has drop {}

fun init(otw: DISPLAY, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);
    // Transfer Publisher to deployer. Can be used later to register Display V2.
    transfer::public_transfer(publisher, tx_context::sender(ctx));
}
```

Note: Display V2 registration for Bounty<T>, ClaimTicket, VerifierCap will be done post-deployment using the Publisher object. The generic type `T` makes compile-time Display registration complex — defer to a separate PTB after first deployment.

- [ ] **Step 2: Verify build**

Run: `sui move build`
Expected: Build Successful

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/sources/display.move
git commit -m "feat(bounty): display module — Publisher claim for Display V2"
```

---

## Task 12: Monkey Tests

**Files:**
- Create: `bounty_escrow/tests/test_monkey.move`

- [ ] **Step 1: Write extreme/edge-case tests**

```move
#[test_only]
module bounty_escrow::test_monkey;

use sui::test_scenario::{Self as ts};
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
use bounty_escrow::verifier::VerifierCap;
use bounty_escrow::escrow;

const CREATOR: address = @0xA;
const VERIFIER: address = @0xB;

#[test]
fun test_reward_amount_1_min_cleanup() {
    // reward=1, cleanup_bps=1 → cleanup_reward should be min 1 (not 0)
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Tiny".to_string(), b"desc".to_string(), coin,
        1, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 1,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Advance past grace period and expire
    clock::set_for_testing(&mut clock, 1_000_000_000 + 86_400_000 + 86_400_000 + 1);
    ts::next_tx(&mut scenario, @0xF); // random caller
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    bounty::expire<SUI>(&mut bounty, &clock, ts::ctx(&mut scenario));
    // Should succeed — caller gets cleanup_reward=1, creator gets 0
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_zero_stake_full_lifecycle() {
    // required_stake = 0
    let mut scenario = ts::begin(CREATOR);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
    clock::set_for_testing(&mut clock, 1_000_000_000);

    ts::next_tx(&mut scenario, CREATOR);
    let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
    bounty::create<SUI>(
        b"Free".to_string(), b"desc".to_string(), coin,
        1000, 0, 1,
        1_000_000_000 + 86_400_000, 86_400_000, 100,
        VERIFIER, &clock, ts::ctx(&mut scenario),
    );

    // Claim with 0 stake
    ts::next_tx(&mut scenario, @0xC);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let stake = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
    bounty::claim<SUI>(&mut bounty, stake, &clock, ts::ctx(&mut scenario));
    ts::return_shared(bounty);

    // Approve
    ts::next_tx(&mut scenario, VERIFIER);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let cap = ts::take_from_sender<VerifierCap>(&scenario);
    bounty::approve<SUI>(&mut bounty, @0xC, &cap, &clock, ts::ctx(&mut scenario));
    ts::return_to_sender(&scenario, cap);
    ts::return_shared(bounty);

    // Claim reward
    ts::next_tx(&mut scenario, @0xC);
    let mut bounty = ts::take_shared<Bounty<SUI>>(&scenario);
    let ticket = ts::take_from_sender<ClaimTicket>(&scenario);
    bounty::claim_reward<SUI>(&mut bounty, ticket, ts::ctx(&mut scenario));
    assert!(bounty::escrow_value(&bounty) == 0);
    ts::return_shared(bounty);

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_cleanup_reward_u128_no_overflow() {
    // Verify u128 intermediate prevents overflow
    let result = escrow::calculate_cleanup_reward(18_446_744_073_709_551_615, 1000);
    // Should not abort. Result = u64::MAX * 1000 / 10000 = u64::MAX / 10
    assert!(result > 0);
}

#[test]
fun test_cleanup_reward_zero_bps() {
    let result = escrow::calculate_cleanup_reward(1000, 0);
    assert!(result == 0);
}

#[test]
fun test_cleanup_reward_min_floor() {
    // Small amount, should return 1 not 0
    let result = escrow::calculate_cleanup_reward(99, 1);
    assert!(result == 1);
}

// === Missing monkey tests from spec ===

#[test]
fun test_max_claims_100_all_abandon() {
    // Create with max_claims=100, have 100 different addresses claim, then all abandon
    // Verify VecSet/VecMap handle 100 entries and stake_pool accounting is correct
    // (Use loop with address generation: @0x100..@0x1FF)
}

#[test]
fun test_shortest_deadline() {
    // deadline = now + MIN_DEADLINE_DURATION (exactly 1 hour)
    // Should succeed
}

#[test]
fun test_coin_change_returned() {
    // Create with coin value > reward * max_claims
    // Verify change is returned to creator
}

#[test]
fun test_claim_abandon_reclaim_cycle() {
    // 5 different hunters claim and abandon, then 5 new hunters claim
    // claimed_hunters should have 10 entries (> max_claims=5)
    // Verify all state is consistent
}

#[test]
fun test_approve_then_expire_without_claim_reward() {
    // create → claim → approve → (deadline+grace passes) → expire
    // Hunter was approved but never called claim_reward
    // Verify: stake forfeited, escrow returned to creator, approved_hunters cleared
}
```

- [ ] **Step 2: Run all tests**

Run: `sui move test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/tests/test_monkey.move
git commit -m "test(bounty): monkey tests — edge cases, overflow, zero-stake"
```

---

## Task 13: Integration Tests

**Files:**
- Create: `bounty_escrow/tests/test_integration.move`

- [ ] **Step 1: Write full lifecycle integration tests**

Cover all flows from spec Section 9:
1. Happy path: create → claim → approve → claim_reward
2. Creator 違約: create → claim → cancel → withdraw_penalty → withdraw_remaining
3. Hunter 擺爛: create → claim → (deadline+grace) → expire
4. 多人部分完成: create(max=3) → 3x claim → 1x approve+claim_reward → 1x abandon → expire
5. 滿額後 abandon 重開: create(max=1) → claim → abandon → new claim → approve → claim_reward
6. Grace period 驗收: create → claim → (past deadline) → approve → claim_reward

Each test should verify all Balance values (escrow, stake_pool) at every step and final account balances.

- [ ] **Step 2: Run all tests with gas tracking**

Run: `sui move test --gas-limit 1000000000`
Expected: ALL PASS, note gas usage for cancel/expire with multiple claims

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/tests/test_integration.move
git commit -m "test(bounty): integration tests — all lifecycle scenarios"
```

---

## Task 14: Final Build + Deploy to Devnet

**Files:**
- No new files

- [ ] **Step 1: Full build verification**

Run: `sui move build`
Expected: Build Successful, no warnings

- [ ] **Step 2: Run complete test suite**

Run: `sui move test`
Expected: ALL PASS

- [ ] **Step 3: Deploy to devnet**

Run: `sui client publish --gas-budget 100000000`
Expected: Published successfully. Record package ID.

- [ ] **Step 4: Commit any final adjustments**

```bash
git add -A
git commit -m "chore(bounty): final build verification + ready for devnet"
```

---

## Dependency Graph

```
Task 1 (scaffold + constants)
  └→ Task 2 (escrow)
  └→ Task 3 (verifier)
       └→ Task 4 (bounty structs + create)
            └→ Task 5 (claim)
                 └→ Task 6 (approve + claim_reward)
                 └→ Task 7 (abandon)
                 └→ Task 8 (cancel + withdraw)
                 └→ Task 9 (expire)
                      └→ Task 10 (destroy cleanup)
            └→ Task 11 (display)
  Task 12 (monkey tests) — after Tasks 2, 6-9
  Task 13 (integration tests) — after all functional tasks
  Task 14 (final build + deploy) — after all tests
```

Tasks 6, 7, 8, 9 can be parallelized (independent functions, all depend on Task 5).
Task 11 can be parallelized with Tasks 5-10.
