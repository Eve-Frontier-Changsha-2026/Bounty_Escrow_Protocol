# v7 Encrypted Bounty Details — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Seal-encrypted classified details, task type UI, and targeted kill support to the Bounty Escrow Protocol.

**Architecture:** 2 new Move modules (encrypted_details, extensions to task_type), composable create pattern (owned→configure→share), Seal threshold encryption via @mysten/seal with Mysten testnet public key servers, 2-step TX for encrypted bounties.

**Tech Stack:** SUI Move 2024, @mysten/seal, @mysten/sui v2.9, React 19, TanStack Query, dapp-kit-react v2, Tailwind CSS 4

**Spec:** `docs/superpowers/specs/2026-03-25-v7-encrypted-details-design.md`

---

## Phase 1: Move Contract Changes

### Task 1: Add v7 error codes and limits to constants.move

**Files:**
- Modify: `bounty_escrow/sources/constants.move`
- Test: existing tests should still pass

- [ ] **Step 1: Add error codes and limits**

At the end of `constants.move`, append:

```move
// === v7 Error Codes ===
public fun e_victim_mismatch(): u64 { 94 }
public fun e_encrypted_details_already_set(): u64 { 95 }
public fun e_encrypted_details_not_set(): u64 { 96 }
public fun e_encrypted_payload_too_large(): u64 { 97 }
public fun e_criteria_encrypted_manual_only(): u64 { 98 }

// === v7 Limits ===
public fun max_encrypted_details_size(): u64 { 4096 }
```

- [ ] **Step 2: Build and test**

Run: `cd bounty_escrow && sui move build && sui move test 2>&1 | tail -3`
Expected: 229 tests pass, zero regression

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/sources/constants.move
git commit -m "feat(v7): add error codes 94-98 and max_encrypted_details_size"
```

---

### Task 2: Add TargetVictimKey + EncryptionStateKey to task_type.move

**Files:**
- Modify: `bounty_escrow/sources/task_type.move`

- [ ] **Step 1: Add structs after existing BuildCriteria**

```move
// === v7: Target Victim (separate DF, no BCS break to KillCriteria) ===

public struct TargetVictimKey() has copy, drop, store;
public struct TargetVictim has copy, drop, store {
    victim_id: u64,
}

// === v7: Encryption State ===

public struct EncryptionStateKey() has copy, drop, store;
public struct EncryptionState has copy, drop, store {
    is_encrypted: bool,
    encrypted_at: u64,
}
```

- [ ] **Step 2: Add set_target_victim function**

After `set_build_criteria`:

```move
/// Set target victim for KILL bounty. Creator only, requires KILL task type.
public fun set_target_victim<T>(
    bounty: &mut Bounty<T>,
    victim_id: u64,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open(),
        constants::e_task_type_requires_open());
    assert!(bounty_escrow::bounty::active_claims(bounty) == 0,
        constants::e_task_type_has_active_claims());

    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(dynamic_field::exists_(uid, TaskTypeKey()), constants::e_missing_criteria());

    let config = dynamic_field::borrow<TaskTypeKey, TaskTypeConfig>(uid, TaskTypeKey());
    assert!(config.task_type == constants::task_type_kill(), constants::e_wrong_task_type());
    assert!(!dynamic_field::exists_(uid, TargetVictimKey()), constants::e_criteria_already_set());

    dynamic_field::add(uid, TargetVictimKey(), TargetVictim { victim_id });
}
```

- [ ] **Step 3: Add set_encryption_state function**

```move
/// Mark bounty criteria as encrypted. Creator only, one-time.
public fun set_encryption_state<T>(
    bounty: &mut Bounty<T>,
    is_encrypted: bool,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(ctx.sender() == bounty_escrow::bounty::creator(bounty), constants::e_not_creator());
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open(),
        constants::e_task_type_requires_open());
    assert!(bounty_escrow::bounty::active_claims(bounty) == 0,
        constants::e_task_type_has_active_claims());
    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, EncryptionStateKey()), constants::e_criteria_already_set());

    dynamic_field::add(uid, EncryptionStateKey(), EncryptionState {
        is_encrypted,
        encrypted_at: sui::clock::timestamp_ms(clock),
    });
}
```

- [ ] **Step 4: Add accessors**

```move
/// Check if criteria are encrypted for this bounty.
public fun is_criteria_encrypted<T>(bounty: &Bounty<T>): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    if (dynamic_field::exists_(uid, EncryptionStateKey())) {
        dynamic_field::borrow<EncryptionStateKey, EncryptionState>(uid, EncryptionStateKey()).is_encrypted
    } else {
        false
    }
}

/// Borrow target victim. Aborts if not set.
public(package) fun borrow_target_victim<T>(bounty: &Bounty<T>): &TargetVictim {
    let uid = bounty_escrow::bounty::uid(bounty);
    assert!(dynamic_field::exists_(uid, TargetVictimKey()), constants::e_missing_criteria());
    dynamic_field::borrow<TargetVictimKey, TargetVictim>(uid, TargetVictimKey())
}

public fun target_victim_id(tv: &TargetVictim): u64 { tv.victim_id }
```

- [ ] **Step 5: Build and test**

Run: `sui move build && sui move test 2>&1 | tail -3`
Expected: 229 pass

- [ ] **Step 6: Commit**

```bash
git add bounty_escrow/sources/task_type.move
git commit -m "feat(v7): add TargetVictimKey, EncryptionStateKey DFs to task_type"
```

---

### Task 3: Create encrypted_details.move

**Files:**
- Create: `bounty_escrow/sources/encrypted_details.move`

- [ ] **Step 1: Write the full module**

```move
/// Encrypted bounty details via Seal protocol.
/// Creator stores Seal-encrypted payload; hunters decrypt after claiming.
module bounty_escrow::encrypted_details;

use sui::clock::Clock;
use sui::event;
use sui::dynamic_field;
use bounty_escrow::constants;
use bounty_escrow::bounty::Bounty;

// === DF Key ===

public struct EncryptedDetailsKey() has copy, drop, store;

// === DF Value ===

public struct EncryptedDetails has copy, drop, store {
    encrypted_payload: vector<u8>,
    created_at: u64,
}

// === Seal Viewer Receipt ===

public struct BountyViewerReceipt has key, store {
    id: UID,
    viewer: address,
    bounty_id: ID,
}

// === Events ===

public struct EncryptedDetailsSetEvent has copy, drop {
    bounty_id: ID,
    creator: address,
    payload_size: u64,
}

public struct ViewerReceiptMintedEvent has copy, drop {
    bounty_id: ID,
    receipt_id: ID,
    viewer: address,
}

// === Core Functions ===

/// Store encrypted details on a bounty. Creator only, one-time, ≤4KB.
public fun set_encrypted_details<T>(
    bounty: &mut Bounty<T>,
    encrypted_payload: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let creator = bounty_escrow::bounty::creator(bounty);
    assert!(ctx.sender() == creator, constants::e_not_creator());
    assert!(bounty_escrow::bounty::status(bounty) == constants::status_open(),
        constants::e_bounty_not_open());
    assert!(bounty_escrow::bounty::active_claims(bounty) == 0,
        constants::e_task_type_has_active_claims());

    let payload_size = encrypted_payload.length();
    assert!(payload_size > 0, constants::e_encrypted_details_not_set());
    assert!(payload_size <= constants::max_encrypted_details_size(),
        constants::e_encrypted_payload_too_large());

    let uid = bounty_escrow::bounty::uid_mut(bounty);
    assert!(!dynamic_field::exists_(uid, EncryptedDetailsKey()),
        constants::e_encrypted_details_already_set());

    dynamic_field::add(uid, EncryptedDetailsKey(), EncryptedDetails {
        encrypted_payload,
        created_at: sui::clock::timestamp_ms(clock),
    });

    event::emit(EncryptedDetailsSetEvent {
        bounty_id: object::id(bounty),
        creator,
        payload_size,
    });
}

/// Mint a BountyViewerReceipt for the calling hunter.
public fun mint_viewer_receipt<T>(
    bounty: &Bounty<T>,
    ctx: &mut TxContext,
) {
    let hunter = ctx.sender();
    assert!(bounty_escrow::bounty::is_active_hunter(bounty, hunter),
        constants::e_hunter_not_active());

    let bounty_id = object::id(bounty);
    let receipt = BountyViewerReceipt {
        id: object::new(ctx),
        viewer: hunter,
        bounty_id,
    };
    let receipt_id = object::id(&receipt);

    transfer::transfer(receipt, hunter);

    event::emit(ViewerReceiptMintedEvent {
        bounty_id,
        receipt_id,
        viewer: hunter,
    });
}

/// Seal key server entry point. Validates namespace prefix = bounty_id.
entry fun seal_approve_bounty(id: vector<u8>, receipt: &BountyViewerReceipt) {
    let bounty_id_bytes = object::id_to_bytes(&receipt.bounty_id);
    let bounty_id_len = bounty_id_bytes.length();
    assert!(id.length() >= bounty_id_len, constants::e_seal_namespace_too_short());

    let mut i = 0;
    while (i < bounty_id_len) {
        assert!(id[i] == bounty_id_bytes[i], constants::e_seal_namespace_mismatch());
        i = i + 1;
    };
}

/// Destroy a BountyViewerReceipt (cleanup).
public fun burn_viewer_receipt(receipt: BountyViewerReceipt) {
    let BountyViewerReceipt { id, .. } = receipt;
    id.delete();
}

// === Accessors ===

public fun has_encrypted_details<T>(bounty: &Bounty<T>): bool {
    let uid = bounty_escrow::bounty::uid(bounty);
    dynamic_field::exists_(uid, EncryptedDetailsKey())
}

public fun get_encrypted_payload<T>(bounty: &Bounty<T>): &vector<u8> {
    let uid = bounty_escrow::bounty::uid(bounty);
    &dynamic_field::borrow<EncryptedDetailsKey, EncryptedDetails>(uid, EncryptedDetailsKey()).encrypted_payload
}

public fun receipt_viewer(receipt: &BountyViewerReceipt): address { receipt.viewer }
public fun receipt_bounty_id(receipt: &BountyViewerReceipt): ID { receipt.bounty_id }
```

- [ ] **Step 2: Build**

Run: `sui move build 2>&1 | tail -5`
Expected: Build success

- [ ] **Step 3: Commit**

```bash
git add bounty_escrow/sources/encrypted_details.move
git commit -m "feat(v7): add encrypted_details module with Seal integration"
```

---

### Task 4: Add encryption + victim checks to verify modules

**Files:**
- Modify: `bounty_escrow/sources/verify_kill.move`
- Modify: `bounty_escrow/sources/verify_delivery.move`
- Modify: `bounty_escrow/sources/verify_build.move`

- [ ] **Step 1: Add imports to verify_kill.move**

Add after existing imports:

```move
use bounty_escrow::task_type::{TargetVictimKey, TargetVictim, EncryptionStateKey, EncryptionState};
```

- [ ] **Step 2: Add encryption + victim checks to verify_kill**

Insert after `assert!(task_type::get_task_type(bounty) == constants::task_type_kill(), ...)` and before `assert!(bounty::is_active_hunter(...))`:

```move
    // 1b. Block auto-verify if criteria are encrypted
    // NOTE: Use inline bounty::uid(bounty) — do NOT bind to a local.
    // A local &UID would conflict with the later bounty::uid_mut() mutable borrow
    // for killmail replay protection. Inline temporaries are dropped immediately.
    if (dynamic_field::exists_(bounty::uid(bounty), EncryptionStateKey())) {
        let enc = dynamic_field::borrow<EncryptionStateKey, EncryptionState>(
            bounty::uid(bounty), EncryptionStateKey()
        );
        assert!(!enc.is_encrypted, constants::e_criteria_encrypted_manual_only());
    };
```

Insert after the loss_type check block (after `};` closing the criteria_loss check), before killmail replay protection:

```move
    // 7b. Target victim filter (if set)
    // Same pattern: inline bounty::uid(bounty) to avoid borrow conflict with uid_mut below
    if (dynamic_field::exists_(bounty::uid(bounty), TargetVictimKey())) {
        let target = dynamic_field::borrow<TargetVictimKey, TargetVictim>(
            bounty::uid(bounty), TargetVictimKey()
        );
        assert!(
            in_game_id::item_id(&killmail.victim_id()) == target.victim_id,
            constants::e_victim_mismatch(),
        );
    };
```

- [ ] **Step 3: Add encryption check to verify_delivery.move**

Add import:
```move
use bounty_escrow::task_type::{EncryptionStateKey, EncryptionState};
```

Insert after task_type check, before hunter check:
```move
    // 1b. Block auto-verify if criteria are encrypted
    let uid_ref = bounty::uid(bounty);
    if (dynamic_field::exists_(uid_ref, EncryptionStateKey())) {
        let enc = dynamic_field::borrow<EncryptionStateKey, EncryptionState>(uid_ref, EncryptionStateKey());
        assert!(!enc.is_encrypted, constants::e_criteria_encrypted_manual_only());
    };
```

- [ ] **Step 4: Add encryption check to verify_build.move**

Same pattern as verify_delivery — add import + encryption check after task_type check.
Use inline `bounty::uid(bounty)` to avoid borrow conflicts (same as verify_kill).

- [ ] **Step 5: Build and test**

Run: `sui move build && sui move test 2>&1 | tail -3`
Expected: 229 pass (existing tests unaffected — they don't set EncryptionState)

- [ ] **Step 6: Commit**

```bash
git add bounty_escrow/sources/verify_kill.move bounty_escrow/sources/verify_delivery.move bounty_escrow/sources/verify_build.move
git commit -m "feat(v7): add encryption state + target victim checks to verify modules"
```

---

### Task 5: Refactor bounty.move — composable create pattern

**Files:**
- Modify: `bounty_escrow/sources/bounty.move`

- [ ] **Step 1: Refactor create_bounty_internal to NOT share**

Currently `create_bounty_internal` calls `transfer::share_object(bounty)` at line ~431. Change it to return `(Bounty<T>, Coin<T>, ID)` without sharing:

In the existing `create_bounty_internal`, replace:
```move
    // --- Share bounty ---
    transfer::share_object(bounty);

    (change, bounty_id)
```
with:
```move
    (bounty, change, bounty_id)
```

Update return type from `(Coin<T>, ID)` to `(Bounty<T>, Coin<T>, ID)`.

- [ ] **Step 2: Update existing callers**

`create_bounty_with_id` — update to share after internal:
```move
public fun create_bounty_with_id<T>(...) -> (Coin<T>, ID) {
    let (bounty, change, bounty_id) = create_bounty_internal(...);
    transfer::share_object(bounty);
    (change, bounty_id)
}
```

`create_bounty` — same pattern:
```move
public fun create_bounty<T>(...) -> Coin<T> {
    let (change, _id) = create_bounty_with_id(...);
    change
}
```

`create` — already calls `create_bounty`, no change needed.

- [ ] **Step 3: Add create_bounty_owned + share_bounty**

```move
/// Create bounty as owned object (not shared). Caller configures then shares.
public fun create_bounty_owned<T>(
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
): (Bounty<T>, Coin<T>) {
    let (bounty, change, _id) = create_bounty_internal(
        title, description, coin,
        reward_amount, required_stake, max_claims,
        deadline, grace_period, cleanup_reward_bps,
        verifier_addr, clock, ctx,
    );
    (bounty, change)
}

/// Share a configured bounty. Call after all setup is done.
public fun share_bounty<T>(bounty: Bounty<T>) {
    transfer::share_object(bounty);
}
```

- [ ] **Step 4: Build and test**

Run: `sui move build && sui move test 2>&1 | tail -3`
Expected: 229 pass (refactor is behavior-preserving — existing callers still share)

- [ ] **Step 5: Commit**

```bash
git add bounty_escrow/sources/bounty.move
git commit -m "feat(v7): add create_bounty_owned + share_bounty composable pattern"
```

---

### Task 6: Write Move tests for v7 features

**Files:**
- Create: `bounty_escrow/tests/test_encrypted_details.move`
- Modify: `bounty_escrow/tests/test_verify_kill.move` (extend)

- [ ] **Step 1: Write test_encrypted_details.move**

Tests to cover:
1. Happy path: set_encrypted_details + has_encrypted_details + get_encrypted_payload
2. Creator-only guard (non-creator → abort)
3. One-time write guard (second set → abort)
4. Payload too large (>4096 → abort)
5. Payload empty (0 bytes → abort)
6. mint_viewer_receipt happy path (active hunter gets receipt)
7. mint_viewer_receipt non-hunter (→ abort)
8. seal_approve_bounty happy path (matching namespace)
9. seal_approve_bounty wrong namespace (→ abort)
10. burn_viewer_receipt (cleanup)
11. Composable create: create_bounty_owned → set_task_type → set_encrypted_details → share_bounty

- [ ] **Step 2: Extend test_verify_kill.move**

Add tests:
1. verify_kill with target_victim match → pass
2. verify_kill with target_victim mismatch → abort e_victim_mismatch
3. verify_kill with encryption_state(is_encrypted=true) → abort e_criteria_encrypted_manual_only
4. verify_kill with encryption_state(is_encrypted=false) → pass (no block)

- [ ] **Step 3: Extend test_task_type.move (if exists) or add to test_encrypted_details.move**

Add tests for new task_type functions:
1. set_target_victim happy path (KILL bounty + creator)
2. set_target_victim wrong task type (DELIVERY bounty → abort e_wrong_task_type)
3. set_target_victim duplicate set → abort e_criteria_already_set
4. set_target_victim non-creator → abort e_not_creator
5. set_encryption_state happy path
6. set_encryption_state duplicate set → abort e_criteria_already_set
7. is_criteria_encrypted returns false when no DF
8. is_criteria_encrypted returns true when set

- [ ] **Step 4: Add encryption check tests for verify_delivery and verify_build**

Add tests:
1. verify_delivery with encryption_state(is_encrypted=true) → abort e_criteria_encrypted_manual_only
2. verify_build with encryption_state(is_encrypted=true) → abort e_criteria_encrypted_manual_only

- [ ] **Step 5: Run all tests**

Run: `sui move test 2>&1 | tail -5`
Expected: All tests pass (target 255+: 229 existing + ~26 new)

- [ ] **Step 6: Commit**

```bash
git add bounty_escrow/tests/
git commit -m "test(v7): add encrypted_details + extended verify_kill tests"
```

---

## Phase 2: Deploy v7 to Testnet

### Task 7: Build, test, upgrade

- [ ] **Step 1: Full build + test**

```bash
cd bounty_escrow
sui move build
sui move test
```

- [ ] **Step 2: Upgrade to testnet**

```bash
sui client upgrade --upgrade-capability 0x10e4164c6dae28a5a861865852c794c462f1085bf277219a4e7eac47bcc8b7e9 --gas-budget 500000000
```

Record V7_PACKAGE_ID from output.

- [ ] **Step 3: Verify on-chain**

```bash
sui client object <V7_PACKAGE_ID> --json | python3 -c "
import json, sys
pkg = json.load(sys.stdin)['data']['Package']
print('Modules:', sorted(pkg['module_map'].keys()))
"
```

Expected: modules list includes `encrypted_details`

- [ ] **Step 4: Commit Published.toml**

```bash
git add bounty_escrow/Published.toml
git commit -m "chore: record v7 testnet deployment"
```

---

## Phase 3: Frontend — Config + Hooks + PTB Builders

### Task 8: Update frontend config and add Seal config

**Files:**
- Modify: `frontend/src/config/contracts.ts`
- Create: `frontend/src/config/seal.ts`
- Modify: `frontend/src/lib/constants.ts`
- Modify: `frontend/src/lib/types.ts`

- [ ] **Step 1: Update contracts.ts with V7_PACKAGE_ID**

Add after V5_PACKAGE_ID:
```typescript
export const V7_PACKAGE_ID = '<V7_PACKAGE_ID_FROM_DEPLOY>';
```

Update PACKAGE_ID to V7 value for function calls. Add MODULE entries for new modules.

- [ ] **Step 2: Create config/seal.ts**

```typescript
export const SEAL_CONFIG = {
  packageId: V7_PACKAGE_ID,
  serverConfigs: [
    { objectId: '0x73d05d62c18d9374e3ea529e8e0ed6161da1a141a94d3f76ae3fe4e99356db75', weight: 1 },
    { objectId: '0xf5d14a81a982144ae441cd7d64b09027f116a468bd36e7eca494f750591623c8', weight: 1 },
  ],
  threshold: 2,
  verifyKeyServers: false,
} as const;
```

- [ ] **Step 3: Add task type labels + error codes to constants.ts**

- [ ] **Step 4: Add types to types.ts**

- [ ] **Step 5: Install @mysten/seal**

```bash
cd frontend && npm install @mysten/seal
```

- [ ] **Step 6: Type check**

```bash
npx tsc --noEmit
```

- [ ] **Step 7: Commit**

---

### Task 9: Add DF-reading hooks

**Files:**
- Create: `frontend/src/hooks/useTaskType.ts`
- Create: `frontend/src/hooks/useCriteria.ts`
- Create: `frontend/src/hooks/useTargetVictim.ts`
- Create: `frontend/src/hooks/useEncryptionState.ts`
- Create: `frontend/src/hooks/useEncryptedDetails.ts`
- Create: `frontend/src/hooks/useViewerReceipt.ts`

Each hook follows the existing pattern from `useProofSubmission.ts` / `useArbitratorConfig.ts`:
- `useQuery` with `getDynamicFieldObject` or `getOwnedObjects`
- Correct DF type references (V5_PACKAGE_ID for task type keys, V7_PACKAGE_ID for new keys)
- Nested field parsing with `(fields.value as Record<string, unknown>)?.fields ?? fields.value`

- [ ] **Step 1: Write useTaskType hook**
- [ ] **Step 2: Write useCriteria hook** (reads KillCriteria/DeliveryCriteria/BuildCriteria based on taskType)
- [ ] **Step 3: Write useTargetVictim hook**
- [ ] **Step 4: Write useEncryptionState hook**
- [ ] **Step 5: Write useEncryptedDetails hook** (returns raw encrypted bytes)
- [ ] **Step 6: Write useViewerReceipt hook** (queries owned BountyViewerReceipt objects matching bountyId)
- [ ] **Step 7: Type check + commit**

---

### Task 10: Add PTB builders

**Files:**
- Create: `frontend/src/lib/ptb/create-full.ts` (TX1: create_bounty_owned + share_bounty)
- Create: `frontend/src/lib/ptb/set-task-type.ts`
- Create: `frontend/src/lib/ptb/set-criteria.ts`
- Create: `frontend/src/lib/ptb/set-encryption-state.ts`
- Create: `frontend/src/lib/ptb/set-encrypted-details.ts` (TX2)
- Create: `frontend/src/lib/ptb/mint-viewer-receipt.ts`

Each builder follows existing pattern from `src/lib/ptb/create.ts`:
- Returns `Transaction` object
- Uses `PACKAGE_ID` for function call targets
- Uses `DEFAULT_COIN_TYPE` for type args

- [ ] **Step 1: Write buildCreateBountyOwned + buildShareBounty** in `create-full.ts` (TX1 — composable owned create + share)
- [ ] **Step 2: Write buildSetTaskType** in `set-task-type.ts`
- [ ] **Step 3: Write buildSetCriteria** in `set-criteria.ts` (Kill/Delivery/Build + TargetVictim)
- [ ] **Step 4: Write buildSetEncryptionState** in `set-encryption-state.ts`
- [ ] **Step 5: Write buildSetEncryptedDetails** in `set-encrypted-details.ts` (TX2)
- [ ] **Step 6: Write buildMintViewerReceipt** in `mint-viewer-receipt.ts`
- [ ] **Step 7: Type check + commit**

---

### Task 11: Add Seal encrypt/decrypt utilities

**Files:**
- Create: `frontend/src/lib/seal.ts`
- Create: `frontend/src/hooks/useSealDecrypt.ts`

- [ ] **Step 1: Write lib/seal.ts** — `encryptBountyDetails()` and `createSealClient()`
- [ ] **Step 2: Write hooks/useSealDecrypt.ts** — lazy SessionKey + decrypt with TTL
- [ ] **Step 3: Type check + commit**

---

## Phase 4: Frontend — UI Components

### Task 12: Update CreateBountyPage with task type + encrypted details

**Files:**
- Modify: `frontend/src/pages/CreateBountyPage.tsx`

- [ ] **Step 1: Add Task Type dropdown to Mission Basics panel**
- [ ] **Step 2: Add dynamic Criteria panel** (KILL/DELIVERY/BUILD fields with encrypt checkbox)
- [ ] **Step 3: Add Classified Details panel** (instructions + conditions textareas, lock icon)
- [ ] **Step 4: Update form submission** — 2-step TX orchestration with progress UI
- [ ] **Step 5: Visual test in browser** — verify form renders correctly for each task type
- [ ] **Step 6: Commit**

---

### Task 13: Update BountyDetailPage with task type + encrypted details

**Files:**
- Modify: `frontend/src/pages/BountyDetailPage.tsx`

- [ ] **Step 1: Add TaskType badge** to header (uses useTaskType hook)
- [ ] **Step 2: Add Criteria display** (uses useCriteria + useTargetVictim hooks)
- [ ] **Step 3: Add Encrypted Details section** with conditional rendering:
  - Not claimed → lock icon + "Claim to unlock"
  - Claimed, no receipt → [Mint Decrypt Key] button
  - Has receipt → [Decrypt Details] button
  - Decrypted → show instructions + conditions
- [ ] **Step 4: Wire up decrypt flow** (useSealDecrypt + useViewerReceipt)
- [ ] **Step 5: Visual test in browser**
- [ ] **Step 6: Commit**

---

### Task 14: Update Dashboard with task type badges

**Files:**
- Modify: `frontend/src/components/bounty/BountyCard.tsx` (or equivalent list card)

- [ ] **Step 1: Add task type badge to bounty cards**
- [ ] **Step 2: Add encrypted indicator** (lock icon if has encrypted details)
- [ ] **Step 3: Commit**

---

## Phase 5: Integration Test

### Task 15: End-to-end manual test

- [ ] **Step 1: Create CUSTOM bounty without encrypted details** (single TX) — verify backward compat
- [ ] **Step 2: Create KILL bounty with public criteria + target victim** — verify task type badge + criteria display
- [ ] **Step 3: Create KILL bounty with encrypted criteria + classified details** (2-step TX) — verify encryption flow
- [ ] **Step 4: Claim encrypted bounty as hunter** — verify [Mint Decrypt Key] appears
- [ ] **Step 5: Mint receipt + decrypt** — verify Seal decryption shows instructions
- [ ] **Step 6: Verify old v4/v5 bounties** still display correctly (type origin compat)
- [ ] **Step 7: Update progress.md**
