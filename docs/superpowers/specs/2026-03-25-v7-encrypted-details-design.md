# v7 Design Spec — Encrypted Bounty Details + Task Type UI

**Date:** 2026-03-25
**Status:** Approved (pending spec review)
**Scope:** Move contract changes + Frontend UI + Seal integration

---

## 1. Executive Summary

Add Seal-encrypted "classified details" to bounties — detailed task instructions and completion conditions visible only to claimed hunters. Add task type selection and criteria UI to the create bounty form. Add targeted kill support (specific victim ID) for KILL bounties.

### Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Encryption method | Seal (Mysten threshold encryption) | True privacy, decentralized, no backend needed |
| Encrypted content storage | On-chain DF (≤4KB) | Sufficient for text, Walrus interface reserved for future |
| Criteria encryption | Creator's choice per bounty | Public criteria → auto-verify; encrypted criteria → manual proof |
| Target victim field | Separate DF (TargetVictimKey) | Zero BCS compat risk with existing KillCriteria |
| ViewerReceipt | New `BountyViewerReceipt` in new module | Semantic isolation from INTEL's ViewerReceipt |
| Create TX flow | 2-step TX: TX1 create+configure+share, TX2 encrypt+set details | Seal encryption requires bountyId (chicken-and-egg: can't encrypt before bounty exists) |

---

## 2. Move Contract Changes

### 2.1 New Module: `encrypted_details.move`

#### Structs

```move
/// DF key for encrypted bounty details
public struct EncryptedDetailsKey() has copy, drop, store;

/// DF value — Seal-encrypted payload
public struct EncryptedDetails has copy, drop, store {
    encrypted_payload: vector<u8>,  // Seal ciphertext
    created_at: u64,
    // Note: creator omitted — already stored on Bounty struct
}

/// Receipt for Seal decryption authorization — minted to active hunters
public struct BountyViewerReceipt has key, store {
    id: UID,
    viewer: address,    // hunter who can decrypt
    bounty_id: ID,
}
```

#### Events

```move
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
```

#### Functions

```move
/// Store encrypted details on a bounty. Creator only, one-time, ≤4KB.
/// Requires: status=OPEN, active_claims=0, no existing DF.
public fun set_encrypted_details<T>(
    bounty: &mut Bounty<T>,
    encrypted_payload: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext,
)

/// Mint a BountyViewerReceipt for the calling hunter.
/// Requires: caller is active hunter.
/// Multiple mints allowed (receipt is disposable decryption token).
/// Internally calls transfer::transfer(receipt, ctx.sender()) — receipt is sent to hunter.
/// Frontend queries owned BountyViewerReceipt objects to find receipt ID for seal_approve.
public fun mint_viewer_receipt<T>(
    bounty: &Bounty<T>,
    ctx: &mut TxContext,
)

/// Seal key server entry point. Validates namespace prefix = bounty_id.
entry fun seal_approve_bounty(
    id: vector<u8>,
    receipt: &BountyViewerReceipt,
)

/// Check if encrypted details exist for this bounty.
public fun has_encrypted_details<T>(bounty: &Bounty<T>): bool

/// Read encrypted payload (returns ciphertext — public, useless without key).
public fun get_encrypted_payload<T>(bounty: &Bounty<T>): &vector<u8>

/// Destroy a BountyViewerReceipt (cleanup for hunters).
public fun burn_viewer_receipt(receipt: BountyViewerReceipt) {
    let BountyViewerReceipt { id, .. } = receipt;
    id.delete();
}
```

#### Access Control Matrix

| Function | Caller | Guards |
|----------|--------|--------|
| `set_encrypted_details` | Creator | sender == creator, status == OPEN, payload 1..4096 bytes, DF not exists. Note: active_claims==0 is guaranteed if called in TX1 flow (before share), but guard is kept for post-creation calls on shared bounties. |
| `mint_viewer_receipt` | Hunter | is_active_hunter(bounty, sender) |
| `seal_approve_bounty` | Seal key server | receipt.bounty_id prefix matches id bytes |

### 2.2 Modified Module: `task_type.move`

#### New Structs (separate DFs, no BCS break)

```move
/// Optional targeted victim for KILL bounties
public struct TargetVictimKey() has copy, drop, store;
public struct TargetVictim has copy, drop, store {
    victim_id: u64,
}

/// Tracks whether criteria are encrypted
public struct EncryptionStateKey() has copy, drop, store;
public struct EncryptionState has copy, drop, store {
    is_encrypted: bool,
    encrypted_at: u64,
}
```

#### New Functions

```move
/// Set target victim for KILL bounty. Creator only, requires KILL task type.
/// Separate from KillCriteria to avoid BCS layout change.
public fun set_target_victim<T>(
    bounty: &mut Bounty<T>,
    victim_id: u64,
    ctx: &mut TxContext,
)

/// Mark bounty criteria as encrypted. Creator only.
public fun set_encryption_state<T>(
    bounty: &mut Bounty<T>,
    is_encrypted: bool,
    clock: &Clock,
    ctx: &mut TxContext,
)

/// Check if criteria are encrypted for this bounty.
public fun is_criteria_encrypted<T>(bounty: &Bounty<T>): bool

/// Borrow target victim. Returns None-like behavior if DF doesn't exist.
public(package) fun borrow_target_victim<T>(bounty: &Bounty<T>): &TargetVictim
public fun target_victim_id(tv: &TargetVictim): u64
```

### 2.3 Modified Verify Modules

#### `verify_kill.move` — add encryption + victim checks

```move
// NEW: Check encryption state — encrypted criteria bounties must use manual proof
if (dynamic_field::exists_(bounty::uid(bounty), EncryptionStateKey())) {
    let enc = dynamic_field::borrow<EncryptionStateKey, EncryptionState>(
        bounty::uid(bounty), EncryptionStateKey()
    );
    assert!(!enc.is_encrypted, constants::e_criteria_encrypted_manual_only());
};

// ... existing criteria checks ...

// NEW: Check target victim (if TargetVictimKey DF exists)
let uid = bounty::uid(bounty);
if (dynamic_field::exists_(uid, TargetVictimKey())) {
    let target = dynamic_field::borrow<TargetVictimKey, TargetVictim>(uid, TargetVictimKey());
    // victim_id() is confirmed on world::killmail::Killmail (returns TenantItemId)
    assert!(
        in_game_id::item_id(&killmail.victim_id()) == target.victim_id,
        constants::e_victim_mismatch(),
    );
};
```

#### `verify_delivery.move` + `verify_build.move` — add encryption check

Same encryption state check added to both modules (before criteria borrow):

```move
// NEW: Block auto-verify if criteria are encrypted
if (dynamic_field::exists_(bounty::uid(bounty), EncryptionStateKey())) {
    let enc = dynamic_field::borrow<EncryptionStateKey, EncryptionState>(
        bounty::uid(bounty), EncryptionStateKey()
    );
    assert!(!enc.is_encrypted, constants::e_criteria_encrypted_manual_only());
};
```

### 2.4 Modified Module: `bounty.move`

Add composable create pattern. Requires a **new internal path** (`create_bounty_owned_internal`) that constructs the Bounty struct and returns it as an owned value WITHOUT calling `transfer::share_object`. The existing `create_bounty_internal` shares the object and cannot be reused.

```move
/// Create bounty as owned object (NOT shared). Caller configures then shares.
/// Returns (Bounty<T>, Coin<T> change).
/// Internally uses create_bounty_owned_internal (new) — does NOT call share_object.
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
): (Bounty<T>, Coin<T>)

/// Share a configured bounty. Call after all setup is done.
public fun share_bounty<T>(bounty: Bounty<T>) {
    transfer::share_object(bounty);
}
```

> **Note:** Existing `create_bounty_with_id` and `create` remain for backward compat.
> **Implementation note:** Refactor existing `create_bounty_internal` to NOT share, then have existing `create_bounty_with_id` call the refactored internal + share. This avoids code duplication.

### 2.5 Modified Module: `constants.move`

```move
// v7 error codes
public fun e_victim_mismatch(): u64 { 94 }
public fun e_encrypted_details_already_set(): u64 { 95 }
public fun e_encrypted_details_not_set(): u64 { 96 }
public fun e_encrypted_payload_too_large(): u64 { 97 }
public fun e_criteria_encrypted_manual_only(): u64 { 98 }

// v7 limits
public fun max_encrypted_details_size(): u64 { 4096 }
```

### 2.6 Upgrade Compatibility

| Change | Compat | Notes |
|--------|--------|-------|
| KillCriteria struct | Unchanged | No BCS break — victim in separate DF |
| New DFs (TargetVictimKey, EncryptionStateKey, EncryptedDetailsKey) | Additive | Old bounties don't have these DFs → safe |
| New module (encrypted_details) | Additive | New module in upgrade package |
| create_bounty_owned | Additive | New function, existing ones preserved |
| share_bounty | Additive | New function |

**Testnet note:** KillCriteria struct is NOT modified. No migration needed.
**Mainnet note:** Same — fully backward compatible.

---

## 3. Frontend Changes

### 3.1 New Dependencies

```json
{
  "@mysten/seal": "^0.6.0"
}
```

### 3.2 Config Updates

```typescript
// config/contracts.ts — additions
export const V7_PACKAGE_ID = '<deployed_v7_package_id>';

export const ORACLE_REGISTRY_ID = '0x0af29639026b162193914095a729f4fd3d1c1360df9301ba9261ce3390e79231';

export const MODULE = {
  // ... existing
  taskType: `${PACKAGE_ID}::task_type`,
  oracle: `${PACKAGE_ID}::oracle`,
  intelEscrow: `${PACKAGE_ID}::intel_escrow`,
  encryptedDetails: `${PACKAGE_ID}::encrypted_details`,
  verifyKill: `${PACKAGE_ID}::verify_kill`,
  verifyDelivery: `${PACKAGE_ID}::verify_delivery`,
  verifyBuild: `${PACKAGE_ID}::verify_build`,
} as const;

// config/seal.ts — NEW
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

### 3.3 Create Bounty Form — Panel Structure

```
Panel 1: Mission Basics (public)
  - Title (text input, max 256)
  - Description (textarea, max 2048)
  - Task Type (dropdown: CUSTOM / KILL / DELIVERY / BUILD / INTEL)

Panel 2: Task Criteria (dynamic by task type)
  KILL:
    - Solar System ID (u64, 0 = any)
    - Loss Type (dropdown: Any / Ship / Structure)
    - Min Kills (number, default 1)
    - Target Player ID (u64, optional, 0 = any)
    ☑ Encrypt criteria (checkbox)
  DELIVERY:
    - Item Type ID (u64)
    - Min Quantity (number)
    - Target Assembly (address, 0x0 = any)
    ☑ Encrypt criteria
  BUILD:
    - Assembly Type ID (u64)
    - Solar System ID (u64, 0 = any)
    ☑ Encrypt criteria
  INTEL / CUSTOM:
    (no criteria fields)

Panel 3: Classified Details (Seal encrypted, optional)
  🔒 "Only claimed hunters can decrypt this content"
  - Detailed Instructions (textarea, max 4096 chars)
  - Completion Conditions (textarea, max 2048 chars)

Panel 4: Economics (existing)
Panel 5: Timing (existing)
Panel 6: Verifier (existing)
```

### 3.4 Create Bounty PTB — 2-Step TX Flow

Seal encryption requires the bounty ID as namespace prefix. Since bounty ID is generated
during TX1, encryption can only happen after TX1 confirms. This creates a 2-step flow.

**TX1: Create + Configure + Share** (no encrypted details yet)

```typescript
async function buildCreateBountyTx1(params: CreateBountyParams): Promise<Transaction> {
  const tx = new Transaction();
  const [coin] = tx.splitCoins(tx.gas, [tx.pure.u64(totalEscrow)]);

  // 1. Create bounty (returns owned Bounty + change)
  const [bounty, change] = tx.moveCall({
    target: `${PKG}::bounty::create_bounty_owned`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.pure.string(params.title), tx.pure.string(params.description),
      coin, tx.pure.u64(params.rewardAmount), tx.pure.u64(params.requiredStake),
      tx.pure.u64(params.maxClaims), tx.pure.u64(params.deadline),
      tx.pure.u64(params.gracePeriod), tx.pure.u16(params.cleanupRewardBps),
      tx.pure.address(params.verifier), tx.object(CLOCK),
    ],
  });

  // 2. Set task type (if not CUSTOM)
  if (params.taskType !== 0) {
    tx.moveCall({
      target: `${PKG}::task_type::set_task_type`,
      typeArguments: [SUI_TYPE],
      arguments: [bounty, tx.pure.u8(params.taskType), tx.object(CLOCK)],
    });
  }

  // 3. Set criteria (if public)
  if (!params.encryptCriteria && params.taskType === KILL && params.killCriteria) {
    tx.moveCall({
      target: `${PKG}::task_type::set_kill_criteria`,
      typeArguments: [SUI_TYPE],
      arguments: [bounty, tx.pure.u64(params.killCriteria.solarSystemId),
        tx.pure.u8(params.killCriteria.lossType), tx.pure.u64(params.killCriteria.minKills)],
    });
    if (params.killCriteria.targetVictimId > 0) {
      tx.moveCall({
        target: `${PKG}::task_type::set_target_victim`,
        typeArguments: [SUI_TYPE],
        arguments: [bounty, tx.pure.u64(params.killCriteria.targetVictimId)],
      });
    }
  }
  // ... DELIVERY, BUILD criteria similarly

  // 4. Set encryption state (if encrypting — details come in TX2)
  if (params.encryptCriteria || params.hasClassifiedDetails) {
    tx.moveCall({
      target: `${PKG}::task_type::set_encryption_state`,
      typeArguments: [SUI_TYPE],
      arguments: [bounty, tx.pure.bool(params.encryptCriteria), tx.object(CLOCK)],
    });
  }

  // 5. Share bounty
  tx.moveCall({
    target: `${PKG}::bounty::share_bounty`,
    typeArguments: [SUI_TYPE],
    arguments: [bounty],
  });

  // 6. Handle change
  tx.transferObjects([change], tx.pure.address(params.sender));
  return tx;
}
```

**TX2: Encrypt + Set Details** (after TX1 confirms, bountyId known)

```typescript
async function buildSetEncryptedDetailsTx2(
  bountyId: string,
  encryptedPayload: Uint8Array,
): Promise<Transaction> {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PKG}::encrypted_details::set_encrypted_details`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.object(bountyId),
      tx.pure.vector('u8', Array.from(encryptedPayload)),
      tx.object(CLOCK),
    ],
  });
  return tx;
}
```

**Frontend orchestration:**

```typescript
// Step 1: Create bounty
const digest1 = await execute(buildCreateBountyTx1(params));
const bountyId = extractBountyIdFromEvent(digest1); // from BountyCreated event

// Step 2: Encrypt with Seal (now we know bountyId)
if (params.hasClassifiedDetails) {
  const { encryptedBytes, backupKey } = await encryptBountyDetails(
    sealClient, bountyId, classifiedPayload
  );
  showBackupKeyDialog(backupKey); // prompt creator to save

  // Step 3: Store encrypted details on-chain
  const digest2 = await execute(buildSetEncryptedDetailsTx2(bountyId, encryptedBytes));
}
```

**UX:** Show progress indicator — "Step 1/2: Creating bounty..." → "Step 2/2: Encrypting details..."

> **Note:** If bounty has NO classified details (no encryption needed), only TX1 is needed — single TX.
> **Note:** `TxContext` is auto-injected by the SDK for Move functions with `&mut TxContext` as last parameter. PTB builders do not pass it explicitly.
```

### 3.5 Seal Encryption (on create)

```typescript
// lib/seal.ts
import { SealClient } from '@mysten/seal';
import { fromHex, toHex } from '@mysten/sui/utils';

export async function encryptBountyDetails(
  sealClient: SealClient,
  bountyIdHex: string,
  payload: {
    detailedInstructions: string;
    completionConditions: string;
    criteria?: Record<string, unknown>;
  },
): Promise<{ encryptedBytes: Uint8Array; backupKey: Uint8Array }> {
  const nonce = crypto.getRandomValues(new Uint8Array(5));
  const bountyIdBytes = fromHex(bountyIdHex);
  const id = toHex(new Uint8Array([...bountyIdBytes, ...nonce]));

  const plaintext = new TextEncoder().encode(JSON.stringify(payload));

  const { encryptedObject, key } = await sealClient.encrypt({
    threshold: SEAL_CONFIG.threshold,
    packageId: SEAL_CONFIG.packageId,
    id,
    data: plaintext,
  });

  return { encryptedBytes: encryptedObject, backupKey: key };
}
```

### 3.6 Seal Decryption (on view)

```typescript
// hooks/useSealDecrypt.ts
export function useSealDecrypt(bountyId: string | undefined) {
  const { mutateAsync: signPersonalMessage } = useSignPersonalMessage();
  const suiClient = useSuiClient();
  const account = useCurrentAccount();
  const [sessionKey, setSessionKey] = useState<SessionKey | null>(null);
  const [decrypted, setDecrypted] = useState<DecryptedDetails | null>(null);

  const decrypt = useCallback(async (encryptedBytes: Uint8Array, receiptId: string) => {
    if (!account || !bountyId) return;

    // 1. Create or reuse SessionKey
    let key = sessionKey;
    if (!key) {
      key = await SessionKey.create({
        address: account.address,
        packageId: SEAL_CONFIG.packageId,
        ttlMin: 10,
        suiClient,
      });
      const message = key.getPersonalMessage();
      const { signature } = await signPersonalMessage({ message });
      key.setPersonalMessageSignature(signature);
      setSessionKey(key);
      // Auto-expire
      setTimeout(() => setSessionKey(null), 10 * 60 * 1000);
    }

    // 2. Build seal_approve_bounty tx
    const tx = new Transaction();
    const encObj = EncryptedObject.parse(encryptedBytes);
    tx.moveCall({
      target: `${PACKAGE_ID}::encrypted_details::seal_approve_bounty`,
      arguments: [
        tx.pure.vector('u8', fromHex(encObj.id)),
        tx.object(receiptId),
      ],
    });
    const txBytes = await tx.build({ client: suiClient, onlyTransactionKind: true });

    // 3. Decrypt
    const sealClient = new SealClient({ suiClient, ...SEAL_CONFIG });
    const decryptedBytes = await sealClient.decrypt({
      data: encryptedBytes,
      sessionKey: key,
      txBytes,
    });

    // 4. Parse JSON
    const details = JSON.parse(new TextDecoder().decode(decryptedBytes));
    setDecrypted(details);
    return details;
  }, [account, bountyId, sessionKey, suiClient, signPersonalMessage]);

  return { decrypt, decrypted, hasSessionKey: !!sessionKey };
}
```

### 3.7 New Hooks Summary

| Hook | Purpose | DF Type Package |
|------|---------|-----------------|
| `useTaskType(bountyId)` | Read TaskTypeKey DF | V5_PACKAGE_ID |
| `useCriteria(bountyId, taskType)` | Read KillCriteriaKey / DeliveryCriteriaKey / BuildCriteriaKey | V5_PACKAGE_ID |
| `useTargetVictim(bountyId)` | Read TargetVictimKey DF | V7_PACKAGE_ID |
| `useEncryptionState(bountyId)` | Read EncryptionStateKey DF | V7_PACKAGE_ID |
| `useEncryptedDetails(bountyId)` | Read EncryptedDetailsKey DF (ciphertext) | V7_PACKAGE_ID |
| `useViewerReceipt(bountyId)` | Query owned BountyViewerReceipt objects | V7_PACKAGE_ID |
| `useSealDecrypt(bountyId)` | Seal decrypt with lazy SessionKey | — |

### 3.8 New PTB Builders

| Builder | Module | Function |
|---------|--------|----------|
| `buildSetTaskType` | task_type | `set_task_type` |
| `buildSetKillCriteria` | task_type | `set_kill_criteria` |
| `buildSetDeliveryCriteria` | task_type | `set_delivery_criteria` |
| `buildSetBuildCriteria` | task_type | `set_build_criteria` |
| `buildSetTargetVictim` | task_type | `set_target_victim` |
| `buildSetEncryptionState` | task_type | `set_encryption_state` |
| `buildSetEncryptedDetails` | encrypted_details | `set_encrypted_details` |
| `buildMintViewerReceipt` | encrypted_details | `mint_viewer_receipt` |
| `buildCreateBountyOwned` | bounty | `create_bounty_owned` |
| `buildShareBounty` | bounty | `share_bounty` |

### 3.9 Bounty Detail Page — Updated Sections

```
Header
  + Task Type badge (KILL / DELIVERY / BUILD / INTEL / CUSTOM)
  + Criteria summary (if public):
    KILL: "Kill target #12345 in System #42 (Ship)"
    DELIVERY: "Deliver 10x Item #100 to Assembly 0xABC"
    BUILD: "Build Assembly Type #8888 in System #42"
  + If encrypted criteria: "🔒 Criteria encrypted — claim to unlock"

NEW: Classified Details Section
  ├─ Not claimed: "🔒 Claim this bounty to unlock detailed instructions"
  ├─ Claimed, no receipt: [Mint Decrypt Key] button → mint BountyViewerReceipt
  ├─ Has receipt, not decrypted: [🔑 Decrypt Details] → SessionKey sign → decrypt
  └─ Decrypted:
      ┌────────────────────────────────┐
      │ Instructions: ...              │
      │ Conditions: ...                │
      │ Criteria (if encrypted): ...   │
      └────────────────────────────────┘

Timing (existing)
Arbitrator (existing)
Hunters (existing)
Proof (existing)
Actions (existing)
```

---

## 4. Seal Infrastructure

### 4.1 Key Server

Using **Mysten testnet public key servers** — no self-hosted infrastructure needed.

| Server | Object ID | Weight |
|--------|-----------|--------|
| Server 1 | `0x73d05d62c18d9374e3ea529e8e0ed6161da1a141a94d3f76ae3fe4e99356db75` | 1 |
| Server 2 | `0xf5d14a81a982144ae441cd7d64b09027f116a468bd36e7eca494f750591623c8` | 1 |

Threshold: 2-of-2

### 4.2 Encryption Flow

```
Creator fills form → Frontend encrypts payload with SealClient.encrypt()
  → ID = bountyId bytes + 5-byte random nonce
  → threshold = 2
  → packageId = V7_PACKAGE_ID (where seal_approve_bounty lives)
  → Returns: encryptedObject (bytes), backupKey (symmetric)
  → encryptedObject stored on-chain via set_encrypted_details()
  → backupKey shown to creator once ("Save this backup key")
```

### 4.3 Decryption Flow

```
Hunter views bounty detail page
  → Fetches EncryptedDetailsKey DF (ciphertext)
  → If has BountyViewerReceipt: show [Decrypt] button
  → If no receipt: show [Mint Decrypt Key] → calls mint_viewer_receipt
  → On [Decrypt] click:
    1. Create SessionKey (10min TTL) — wallet signs personal message
    2. Build seal_approve_bounty TX (not executed, just bytes)
    3. SealClient.decrypt(data, sessionKey, txBytes)
    4. Parse JSON → display instructions + conditions
```

### 4.4 Walrus Future Interface

```typescript
// lib/storage.ts
interface EncryptedStorage {
  store(payload: Uint8Array): Promise<string>;  // returns storage reference
  fetch(ref: string): Promise<Uint8Array>;       // fetches by reference
}

class OnChainStorage implements EncryptedStorage {
  // Current: store in DF, fetch via RPC
}

// Future:
// class WalrusStorage implements EncryptedStorage {
//   // Store encrypted blob on Walrus, return blobId
//   // Fetch blob by blobId
// }
```

---

## 5. Security Analysis

### 5.1 Attack Vectors & Defenses

| # | Attack | Severity | Defense |
|---|--------|----------|---------|
| 1 | Non-creator sets encrypted details | High | `sender == creator` assert |
| 2 | Non-hunter mints viewer receipt | High | `is_active_hunter()` assert |
| 3 | Cross-bounty receipt reuse | High | `seal_approve_bounty` validates namespace prefix = bounty_id |
| 4 | Encrypted payload DoS (large size) | Medium | `payload.length() <= 4096` assert |
| 5 | Overwrite encrypted details | Medium | DF existence check (one-time write) |
| 6 | Auto-verify on encrypted criteria | Medium | `is_encrypted` check in verify_kill → abort with clear error |
| 7 | Front-run set_encrypted_details | Low | Creator-only guard blocks all non-creators |
| 8 | Multiple receipt minting | Info | Allowed — receipt is disposable decryption token |

### 5.2 Privacy Model

| Data | Visibility | Notes |
|------|-----------|-------|
| Title, description | Public | Always visible |
| Task type (KILL/DELIVERY/etc) | Public | Always visible |
| Criteria (solar_system, loss_type, target_victim) | Creator's choice | Public OR encrypted |
| Detailed instructions | Encrypted | Only claimed hunters can decrypt |
| Completion conditions | Encrypted | Only claimed hunters can decrypt |
| Encrypted payload (ciphertext) | Public | Readable but useless without Seal decryption key |

---

## 6. Type Origin Mapping

| Struct | Defining Package | Notes |
|--------|-----------------|-------|
| Bounty, ClaimTicket, VerifierCap | ORIGINAL_PACKAGE_ID (v1) | Never changes |
| ProofKey, ReviewConfigKey | V3_PACKAGE_ID | |
| ArbitratorConfigKey, DisputeTimestampKey | V4_PACKAGE_ID | |
| TaskTypeKey, KillCriteriaKey, OracleRegistry | V5_PACKAGE_ID | |
| EncryptedDetailsKey, BountyViewerReceipt, TargetVictimKey, EncryptionStateKey | **V7_PACKAGE_ID** | New in this upgrade |

---

## 7. File Impact Summary

### Move (bounty_escrow/)

| File | Action | Changes |
|------|--------|---------|
| `sources/encrypted_details.move` | **NEW** | ~120 lines: structs, set/mint/seal_approve/accessors |
| `sources/task_type.move` | MODIFY | +TargetVictimKey, +EncryptionStateKey, +set_target_victim, +set_encryption_state, +is_criteria_encrypted |
| `sources/verify_kill.move` | MODIFY | +encryption state check, +target victim check |
| `sources/verify_delivery.move` | MODIFY | +encryption state check (block auto-verify if encrypted) |
| `sources/verify_build.move` | MODIFY | +encryption state check (block auto-verify if encrypted) |
| `sources/bounty.move` | MODIFY | +create_bounty_owned (returns owned), +share_bounty, refactor create_bounty_internal |
| `sources/constants.move` | MODIFY | +5 error codes (94-98), +max_encrypted_details_size |

> **V6 note:** V6 (`0x6829...`) only added `create_and_share_registry` to oracle.move. No new error codes or structs. Error codes 94+ are safe for v7.

### Frontend (frontend/src/)

| File | Action | Changes |
|------|--------|---------|
| `config/contracts.ts` | MODIFY | +V7_PACKAGE_ID, +MODULE entries |
| `config/seal.ts` | **NEW** | Seal server config |
| `lib/seal.ts` | **NEW** | encrypt/decrypt helpers |
| `lib/storage.ts` | **NEW** | EncryptedStorage interface + OnChainStorage |
| `lib/constants.ts` | MODIFY | +TASK_TYPE_LABEL, +error codes 94-98 |
| `lib/types.ts` | MODIFY | +TaskType, +Criteria, +EncryptedDetails types |
| `lib/ptb/create-full.ts` | **NEW** | Single-TX composable create |
| `lib/ptb/set-task-type.ts` | **NEW** | |
| `lib/ptb/set-criteria.ts` | **NEW** | Kill/Delivery/Build criteria |
| `lib/ptb/set-encrypted-details.ts` | **NEW** | |
| `lib/ptb/mint-viewer-receipt.ts` | **NEW** | |
| `hooks/useTaskType.ts` | **NEW** | |
| `hooks/useCriteria.ts` | **NEW** | |
| `hooks/useTargetVictim.ts` | **NEW** | |
| `hooks/useEncryptionState.ts` | **NEW** | |
| `hooks/useEncryptedDetails.ts` | **NEW** | |
| `hooks/useViewerReceipt.ts` | **NEW** | |
| `hooks/useSealDecrypt.ts` | **NEW** | Lazy SessionKey + decrypt |
| `pages/CreateBountyPage.tsx` | MODIFY | +Task type selector, +criteria panels, +classified details |
| `pages/BountyDetailPage.tsx` | MODIFY | +Task type badge, +criteria display, +encrypted details section |

---

## 8. Testing Strategy

### Move Tests

| Test File | Coverage |
|-----------|----------|
| `test_encrypted_details.move` | set/mint/seal_approve happy path, creator-only, size limit, one-time write, active hunter check |
| `test_verify_kill.move` (extend) | +target victim match/mismatch, +encryption state check abort |
| `test_task_type.move` (extend) | +set_target_victim, +set_encryption_state |
| `test_composable_create.move` | create_bounty_owned → configure → share_bounty full cycle |
| Red team | Cross-bounty receipt, non-creator griefing, payload DoS, front-run |

### Frontend Tests

| Area | Method |
|------|--------|
| Create form validation | Unit test: required fields, type-specific criteria visibility |
| PTB construction | Unit test: correct move call targets, argument encoding |
| Seal encrypt/decrypt | Integration test with testnet key servers |
| DF type references | Verify V7_PACKAGE_ID for new structs |

---

## 9. Deployment Checklist

1. `sui move build` — verify no errors
2. `sui move test` — verify all tests pass (target: 250+)
3. `sui client upgrade` — deploy v7 to testnet
4. Record V7_PACKAGE_ID
5. Update `frontend/src/config/contracts.ts` with V7_PACKAGE_ID
6. `npm install @mysten/seal` in frontend
7. `npx tsc --noEmit` — verify frontend type-check
8. Manual test: create bounty with encrypted details → claim → decrypt
