# Bounty Escrow Protocol — Integration Guide

> **Package ID (testnet):** `0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16`
> **Version:** 1 · **Edition:** Move 2024

本文件說明上層合約如何引用 `bounty_escrow` 的 public API，並提供三個場景（Intel / PvP / Logistics）的 Move 骨架與 TypeScript PTB 範例。

---

## §1 — Protocol Overview

### Lifecycle 狀態機

```
Open ──claim──▶ Claimed ──approve──▶ (approved set)
  │                │                        │
  │                │                   claim_reward
  │                │                        │
  │                ▼                        ▼
  │            (all slots filled)      Completed
  │
  ├──cancel──▶ Cancelled ──withdraw_penalty──▶ (hunters withdraw)
  │                            └──withdraw_remaining──▶ (creator withdraws)
  │
  └──expire──▶ Expired  (after deadline + grace_period)
```

**狀態碼：** `0=Open` · `1=Claimed` · `2=Completed` · `3=Cancelled` · `4=Expired`

### 核心物件

| Object | Type | Ownership | 說明 |
|--------|------|-----------|------|
| `Bounty<T>` | shared | `share_object` | 主狀態，含 escrow + stake pool |
| `ClaimTicket` | owned | hunter | 接單憑證，claim_reward/abandon/withdraw_penalty 時消耗 |
| `VerifierCap` | owned | verifier | 驗收權限 cap，每個 Bounty 一個 |

### Two-Step Verify

Sui 的 owned-object 限制讓 verifier 無法在同一 tx 中操作 hunter 的 ticket。因此驗收分兩步：

1. **Verifier** 呼叫 `approve_hunter()` — 只需 `&mut Bounty<T>` (shared) + `&VerifierCap` (owned)
2. **Hunter** 呼叫 `claim_reward()` — 傳入自己的 `ClaimTicket` (owned)

---

## §2 — Public API Reference

### Creator Functions

```move
// 建立 Bounty，鎖定 reward_amount × max_claims 到 escrow
// 回傳找零 Coin<T>（composable 版本）
public fun create_bounty<T>(
    title: String,
    description: String,
    coin: Coin<T>,
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,           // timestamp_ms，需在 now+1h ~ now+365d 之間
    grace_period: u64,       // ms，驗收補救期
    cleanup_reward_bps: u16, // 0~1000 (0%~10%)
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<T>

// entry wrapper — 自動處理找零 transfer
public fun create<T>( /* 同上參數 */ )

// 取消 Bounty（creator only）
// 無 hunter 時直接退 escrow；有 hunter 時進入 withdrawal pattern
public fun cancel_bounty<T>(bounty: &mut Bounty<T>, ctx: &mut TxContext)
public fun cancel<T>(bounty: &mut Bounty<T>, ctx: &mut TxContext)

// 取消後，所有 hunter withdraw_penalty 完畢，creator 提取剩餘
public fun withdraw_remaining_bounty<T>(bounty: &mut Bounty<T>, ctx: &mut TxContext)
public fun withdraw_remaining<T>(bounty: &mut Bounty<T>, ctx: &mut TxContext)
```

### Hunter Functions

```move
// 接單：鎖定 stake，取得 ClaimTicket
// 回傳 (ClaimTicket, Coin<T> 找零)（composable 版本）
public fun claim_bounty<T>(
    bounty: &mut Bounty<T>,
    stake_coin: Coin<T>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<T>)

// entry wrapper
public fun claim<T>( /* 同上 */ )

// 已被 approve 後，hunter 領取 reward + 取回 stake
public fun claim_reward_bounty<T>(bounty: &mut Bounty<T>, ticket: ClaimTicket, ctx: &mut TxContext)
public fun claim_reward<T>(bounty: &mut Bounty<T>, ticket: ClaimTicket, ctx: &mut TxContext)

// 主動放棄：stake 沒收給 creator
public fun abandon_bounty<T>(bounty: &mut Bounty<T>, ticket: ClaimTicket, clock: &Clock, ctx: &mut TxContext)
public fun abandon<T>( /* 同上 */ )

// 取消後 hunter 提取：取回 stake + 獲得違約金
public fun withdraw_penalty_bounty<T>(bounty: &mut Bounty<T>, ticket: ClaimTicket, ctx: &mut TxContext)
public fun withdraw_penalty<T>( /* 同上 */ )
```

### Verifier Functions

```move
// 驗收通過：把 hunter 加入 approved set
public fun approve_hunter<T>(
    bounty: &mut Bounty<T>,
    hunter: address,
    cap: &VerifierCap,
    clock: &Clock,
    ctx: &mut TxContext,
)
public fun approve<T>( /* 同上 */ )
```

### Cleanup / Permissionless Functions

```move
// 過期清算：任何人可呼叫，caller 拿 cleanup reward
// 回傳 cleanup reward Coin<T>（composable 版本）
public fun expire_bounty<T>(bounty: &mut Bounty<T>, clock: &Clock, ctx: &mut TxContext): Coin<T>
public fun expire<T>( /* 同上 */ )

// 銷毀已完成 bounty 的 ticket / verifier cap
public fun destroy_ticket<T>(ticket: ClaimTicket, bounty: &Bounty<T>)
public fun destroy_verifier_cap<T>(cap: VerifierCap, bounty: &Bounty<T>)
```

### Read-Only Accessors

```move
public fun status<T>(bounty: &Bounty<T>): u8
public fun creator<T>(bounty: &Bounty<T>): address
public fun reward_amount<T>(bounty: &Bounty<T>): u64
public fun required_stake<T>(bounty: &Bounty<T>): u64
public fun active_claims<T>(bounty: &Bounty<T>): u64
public fun completed_claims<T>(bounty: &Bounty<T>): u64
public fun max_claims<T>(bounty: &Bounty<T>): u64
public fun deadline<T>(bounty: &Bounty<T>): u64
public fun grace_period<T>(bounty: &Bounty<T>): u64
public fun escrow_value<T>(bounty: &Bounty<T>): u64
public fun stake_pool_value<T>(bounty: &Bounty<T>): u64
public fun ticket_bounty_id(ticket: &ClaimTicket): ID
public fun ticket_hunter(ticket: &ClaimTicket): address
public fun ticket_stake_amount(ticket: &ClaimTicket): u64
```

---

## §3 — Generic Integration Pattern

### Move.toml Dependency

```toml
[dependencies]
BountyEscrow = { git = "https://github.com/<org>/bounty-escrow-protocol.git", subdir = "bounty_escrow", rev = "main" }
# 或直接用 published address（testnet）：
# BountyEscrow = { id = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16", version = 1 }
```

### Move Composition Pattern

上層合約透過 `public fun`（非 entry wrapper）組合呼叫：

```move
module my_app::task_manager;

use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};

/// 上層封裝：建立任務同時建立 bounty
public fun create_task(
    title: String,
    description: String,
    payment: Coin<SUI>,
    reward_amount: u64,
    deadline: u64,
    verifier_addr: address,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    // 上層業務邏輯 ...

    // 組合呼叫 bounty_escrow（composable 版本回傳找零）
    let change = bounty::create_bounty<SUI>(
        title,
        description,
        payment,
        reward_amount,
        /*required_stake=*/ 0,
        /*max_claims=*/ 1,
        deadline,
        /*grace_period=*/ 86_400_000, // 1 day
        /*cleanup_reward_bps=*/ 100,  // 1%
        verifier_addr,
        clock,
        ctx,
    );

    change
}
```

**關鍵原則：**
- 使用 `_bounty` 後綴版本（`create_bounty`、`claim_bounty` 等）— 這些回傳值供上層組合
- entry wrapper（`create`、`claim` 等）自動 transfer，適合直接 PTB 呼叫
- `Bounty<T>` 是 generic — 可用任何 coin type，不限 SUI

### TypeScript PTB 基本模式

```typescript
import { Transaction } from "@mysten/sui/transactions";

const BOUNTY_PACKAGE = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16";
const COIN_TYPE = "0x2::sui::SUI";

// === Create Bounty ===
function buildCreateBountyTx(params: {
  title: string;
  description: string;
  coinObjectId: string;
  rewardAmount: bigint;
  requiredStake: bigint;
  maxClaims: bigint;
  deadline: bigint;       // timestamp_ms
  gracePeriod: bigint;    // ms
  cleanupBps: number;
  verifierAddr: string;
}): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: `${BOUNTY_PACKAGE}::bounty::create`,
    typeArguments: [COIN_TYPE],
    arguments: [
      tx.pure.string(params.title),
      tx.pure.string(params.description),
      tx.object(params.coinObjectId),    // Coin<SUI>
      tx.pure.u64(params.rewardAmount),
      tx.pure.u64(params.requiredStake),
      tx.pure.u64(params.maxClaims),
      tx.pure.u64(params.deadline),
      tx.pure.u64(params.gracePeriod),
      tx.pure.u16(params.cleanupBps),
      tx.pure.address(params.verifierAddr),
      tx.object("0x6"),                  // Clock
    ],
  });

  return tx;
}

// === Claim Bounty ===
function buildClaimBountyTx(
  bountyId: string,
  stakeCoinId: string,
): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: `${BOUNTY_PACKAGE}::bounty::claim`,
    typeArguments: [COIN_TYPE],
    arguments: [
      tx.object(bountyId),       // &mut Bounty<SUI>
      tx.object(stakeCoinId),    // Coin<SUI> for stake
      tx.object("0x6"),          // Clock
    ],
  });

  return tx;
}

// === Approve Hunter (Verifier) ===
function buildApproveTx(
  bountyId: string,
  hunterAddr: string,
  verifierCapId: string,
): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: `${BOUNTY_PACKAGE}::bounty::approve`,
    typeArguments: [COIN_TYPE],
    arguments: [
      tx.object(bountyId),        // &mut Bounty<SUI>
      tx.pure.address(hunterAddr),
      tx.object(verifierCapId),   // &VerifierCap
      tx.object("0x6"),           // Clock
    ],
  });

  return tx;
}

// === Claim Reward (Hunter) ===
function buildClaimRewardTx(
  bountyId: string,
  ticketId: string,
): Transaction {
  const tx = new Transaction();

  tx.moveCall({
    target: `${BOUNTY_PACKAGE}::bounty::claim_reward`,
    typeArguments: [COIN_TYPE],
    arguments: [
      tx.object(bountyId),   // &mut Bounty<SUI>
      tx.object(ticketId),   // ClaimTicket (consumed)
    ],
  });

  return tx;
}
```

### Coin Splitting in PTB

當 hunter 只有一個大 coin 但只需質押 `required_stake` 時：

```typescript
const tx = new Transaction();
const [stakeCoin] = tx.splitCoins(tx.object(bigCoinId), [tx.pure.u64(stakeAmount)]);

tx.moveCall({
  target: `${BOUNTY_PACKAGE}::bounty::claim`,
  typeArguments: [COIN_TYPE],
  arguments: [
    tx.object(bountyId),
    stakeCoin,         // 剛切出來的 coin
    tx.object("0x6"),
  ],
});
```

---

## §4 — Scenario: Intel Bounty（Frontier Explorer Hub）

### 場景描述

Corporation 懸賞特定星區情報。Explorer 提交 `IntelReport` 後，由 **Intel Verifier**（可以是自動化 oracle 或管理員）驗收。驗收通過 → Explorer 領取 reward。

```
Corporation ──create_bounty──▶ Bounty<SUI> (shared)
Explorer    ──claim_bounty──▶  ClaimTicket (owned)
Explorer    ──submit intel──▶  IntelReport (Explorer Hub 邏輯)
Verifier    ──approve_hunter──▶ approved set
Explorer    ──claim_reward──▶  💰 reward + stake returned
```

### Move Skeleton

```move
module frontier_explorer_hub::intel_bounty;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};
// use frontier_explorer_hub::intel::{Self, IntelReport};

/// 建立情報懸賞
/// verifier_addr = intel quality oracle 或 admin
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
    // 可在此加入 Explorer Hub 專屬驗證
    // 例如：assert!(title 包含 region code)

    bounty::create_bounty<SUI>(
        title,
        description,
        payment,
        reward_per_report,
        /*required_stake=*/ 0,        // 情報任務不需質押
        max_reporters,
        deadline,
        /*grace_period=*/ 86_400_000, // 1 day
        /*cleanup_reward_bps=*/ 100,  // 1%
        verifier_addr,
        clock,
        ctx,
    )
}

/// Explorer 接單 — 質押為 0 的場景
public fun accept_intel_bounty(
    bounty: &mut Bounty<SUI>,
    zero_coin: Coin<SUI>,  // 0 value coin (required by interface)
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, zero_coin, clock, ctx)
}

/// Verifier 驗收（可由 oracle 自動呼叫）
/// 上層可加入 IntelReport 品質檢查邏輯
// public fun verify_intel(
//     bounty: &mut Bounty<SUI>,
//     report: &IntelReport,
//     hunter: address,
//     cap: &VerifierCap,
//     clock: &Clock,
//     ctx: &mut TxContext,
// ) {
//     // 檢查 report 品質、region match 等
//     bounty::approve_hunter<SUI>(bounty, hunter, cap, clock, ctx);
// }
```

### TypeScript PTB — Intel Bounty 完整 Flow

```typescript
import { Transaction } from "@mysten/sui/transactions";
import { SuiClient } from "@mysten/sui/client";

const BOUNTY_PKG = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16";
const CLOCK = "0x6";
const SUI_TYPE = "0x2::sui::SUI";

// Step 1: Corporation 發布 Intel Bounty
function createIntelBounty(
  coinId: string,
  rewardPerReport: bigint,
  maxReporters: bigint,
  deadlineMs: bigint,
  verifierAddr: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::create`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.pure.string("Intel: Scan Sector J-7"),
      tx.pure.string("Submit terrain & threat data for sector J-7. Min accuracy 85%."),
      tx.object(coinId),
      tx.pure.u64(rewardPerReport),
      tx.pure.u64(0n),                // no stake required
      tx.pure.u64(maxReporters),
      tx.pure.u64(deadlineMs),
      tx.pure.u64(86_400_000n),       // 1 day grace
      tx.pure.u16(100),               // 1% cleanup reward
      tx.pure.address(verifierAddr),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 2: Explorer 接單（stake = 0，需要一個 zero coin）
function claimIntelBounty(bountyId: string): Transaction {
  const tx = new Transaction();
  const [zeroCoin] = tx.splitCoins(tx.gas, [tx.pure.u64(0n)]);
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), zeroCoin, tx.object(CLOCK)],
  });
  return tx;
}

// Step 3: Verifier 驗收
function approveExplorer(
  bountyId: string,
  explorerAddr: string,
  verifierCapId: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::approve`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.object(bountyId),
      tx.pure.address(explorerAddr),
      tx.object(verifierCapId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 4: Explorer 領取 reward
function claimIntelReward(bountyId: string, ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim_reward`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), tx.object(ticketId)],
  });
  return tx;
}
```

---

## §5 — Scenario: PvP Bounty（Fleet Command）

### 場景描述

Fleet Commander 發布擊殺合約（kill order）。傭兵接單需質押保證金。**Battle Judge**（鏈上裁判合約或可信第三方）驗證擊殺證明後批准。

```
Commander   ──create_bounty──▶ Bounty<SUI>     (reward locked)
Mercenary   ──claim_bounty──▶  ClaimTicket      (stake locked)
Mercenary   ──execute kill──▶  (off-chain / game event)
BattleJudge ──approve_hunter──▶ approved
Mercenary   ──claim_reward──▶  💰 reward + stake returned
```

### Move Skeleton

```move
module fleet_command::mercenary;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};

/// 傭兵合約的質押比例：reward 的 10%
const STAKE_RATIO_BPS: u64 = 1000;

/// 發布擊殺合約
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
        stake,                         // 傭兵需質押
        /*max_claims=*/ 3,             // 最多 3 人同時接單
        deadline,
        /*grace_period=*/ 172_800_000, // 2 days（戰鬥結算需要時間）
        /*cleanup_reward_bps=*/ 200,   // 2%
        battle_judge,
        clock,
        ctx,
    )
}

/// 傭兵接單
public fun accept_kill_order(
    bounty: &mut Bounty<SUI>,
    stake_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, stake_coin, clock, ctx)
}

/// 傭兵放棄（stake 沒收 = 逃兵懲罰）
public fun desert(
    bounty: &mut Bounty<SUI>,
    ticket: ClaimTicket,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    bounty::abandon_bounty<SUI>(bounty, ticket, clock, ctx);
}
```

### TypeScript PTB — PvP Bounty Flow

```typescript
const BOUNTY_PKG = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16";
const SUI_TYPE = "0x2::sui::SUI";
const CLOCK = "0x6";

// Step 1: Commander 發布 kill order
function issueKillOrder(
  coinId: string,
  reward: bigint,
  stakeRequired: bigint,
  deadlineMs: bigint,
  battleJudgeAddr: string,
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::create`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.pure.string("Kill Order: Pirate Lord Zephyr"),
      tx.pure.string("Eliminate target in Sector K-9. Proof: wreckage scan data."),
      tx.object(coinId),
      tx.pure.u64(reward),
      tx.pure.u64(stakeRequired),
      tx.pure.u64(3n),               // max 3 mercenaries
      tx.pure.u64(deadlineMs),
      tx.pure.u64(172_800_000n),      // 2 day grace
      tx.pure.u16(200),              // 2% cleanup
      tx.pure.address(battleJudgeAddr),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 2: Mercenary 接單（需質押）
function acceptKillOrder(bountyId: string, bigCoinId: string, stakeAmount: bigint): Transaction {
  const tx = new Transaction();
  const [stakeCoin] = tx.splitCoins(tx.object(bigCoinId), [tx.pure.u64(stakeAmount)]);
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), stakeCoin, tx.object(CLOCK)],
  });
  return tx;
}

// Step 3: Battle Judge 驗證擊殺
function verifyKill(bountyId: string, mercenaryAddr: string, judgeCapId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::approve`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.object(bountyId),
      tx.pure.address(mercenaryAddr),
      tx.object(judgeCapId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 4: Mercenary 領賞
function collectBounty(bountyId: string, ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim_reward`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), tx.object(ticketId)],
  });
  return tx;
}

// Alternative: Commander 取消 kill order
function cancelKillOrder(bountyId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::cancel`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId)],
  });
  return tx;
}
```

---

## §6 — Scenario: Logistics Bounty（Tribal Governance DAO）

### 場景描述

DAO 國庫透過 multi-sig 提案發布後勤任務（資源運輸、設施維修）。任務完成後由 **DAO Council**（multi-sig 地址）作為 verifier 驗收。

```
DAO Council ──(multi-sig)──▶ create_bounty ──▶ Bounty<SUI>
Runner      ──claim_bounty──▶ ClaimTicket (stake = security deposit)
Runner      ──complete task──▶ (off-chain delivery proof)
DAO Council ──(multi-sig)──▶ approve_hunter
Runner      ──claim_reward──▶ 💰 reward + deposit returned
```

### Move Skeleton

```move
module tribal_dao::logistics;

use std::string::String;
use sui::coin::Coin;
use sui::clock::Clock;
use sui::sui::SUI;
use bounty_escrow::bounty::{Self, Bounty, ClaimTicket};

/// 後勤任務類型
const TASK_TRANSPORT: u8 = 0;
const TASK_REPAIR: u8 = 1;
const TASK_SUPPLY: u8 = 2;

/// DAO 發布後勤任務
/// verifier_addr = DAO multi-sig 地址
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
        security_deposit,              // runner 需繳保證金
        /*max_claims=*/ 1,             // 後勤任務通常單人
        deadline,
        /*grace_period=*/ 259_200_000, // 3 days（物流需要緩衝）
        /*cleanup_reward_bps=*/ 50,    // 0.5%
        dao_multisig,
        clock,
        ctx,
    )
}

/// Runner 接單
public fun accept_logistics_task(
    bounty: &mut Bounty<SUI>,
    deposit_coin: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): (ClaimTicket, Coin<SUI>) {
    bounty::claim_bounty<SUI>(bounty, deposit_coin, clock, ctx)
}

/// 查詢任務狀態（read-only，供前端用）
public fun task_status(bounty: &Bounty<SUI>): u8 {
    bounty::status<SUI>(bounty)
}

public fun task_reward(bounty: &Bounty<SUI>): u64 {
    bounty::reward_amount<SUI>(bounty)
}
```

### TypeScript PTB — Logistics Bounty Flow

```typescript
const BOUNTY_PKG = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16";
const SUI_TYPE = "0x2::sui::SUI";
const CLOCK = "0x6";

// Step 1: DAO 發布後勤任務（通常由 multi-sig 提案執行）
function postLogisticsTask(
  treasuryCoinId: string,
  reward: bigint,
  securityDeposit: bigint,
  deadlineMs: bigint,
  daoMultisigAddr: string, // multi-sig 同時作為 verifier
): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::create`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.pure.string("Logistics: Supply Run to Outpost Gamma"),
      tx.pure.string("Deliver 500 units of fuel cells. Proof: docking receipt hash."),
      tx.object(treasuryCoinId),
      tx.pure.u64(reward),
      tx.pure.u64(securityDeposit),
      tx.pure.u64(1n),              // single runner
      tx.pure.u64(deadlineMs),
      tx.pure.u64(259_200_000n),     // 3 day grace
      tx.pure.u16(50),              // 0.5% cleanup
      tx.pure.address(daoMultisigAddr),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 2: Runner 接單
function acceptLogisticsTask(bountyId: string, bigCoinId: string, deposit: bigint): Transaction {
  const tx = new Transaction();
  const [depositCoin] = tx.splitCoins(tx.object(bigCoinId), [tx.pure.u64(deposit)]);
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), depositCoin, tx.object(CLOCK)],
  });
  return tx;
}

// Step 3: DAO Council multi-sig 驗收
// 注意：multi-sig tx 需要收集足夠簽名後再 execute
function approveDelivery(bountyId: string, runnerAddr: string, daoCapId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::approve`,
    typeArguments: [SUI_TYPE],
    arguments: [
      tx.object(bountyId),
      tx.pure.address(runnerAddr),
      tx.object(daoCapId),
      tx.object(CLOCK),
    ],
  });
  return tx;
}

// Step 4: Runner 領取報酬
function collectPayment(bountyId: string, ticketId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::claim_reward`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), tx.object(ticketId)],
  });
  return tx;
}

// Edge case: 任務過期（任何人可清算）
function expireStaleTask(bountyId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${BOUNTY_PKG}::bounty::expire`,
    typeArguments: [SUI_TYPE],
    arguments: [tx.object(bountyId), tx.object(CLOCK)],
  });
  return tx;
}
```

---

## §7 — Events & Indexing

### Event 清單

| Event | 觸發時機 | 關鍵欄位 |
|-------|---------|----------|
| `BountyCreated` | `create_bounty` | `bounty_id`, `creator`, `coin_type`, `reward_amount`, `required_stake`, `max_claims`, `deadline`, `grace_period`, `verifier` |
| `BountyClaimed` | `claim_bounty` | `bounty_id`, `ticket_id`, `hunter`, `stake_amount` |
| `BountyApproved` | `approve_hunter` | `bounty_id`, `hunter`, `verifier` |
| `RewardClaimed` | `claim_reward_bounty` | `bounty_id`, `ticket_id`, `hunter`, `reward_amount`, `stake_returned` |
| `BountyCancelled` | `cancel_bounty` | `bounty_id`, `creator`, `active_claims_at_cancel`, `penalty_per_hunter` |
| `PenaltyWithdrawn` | `withdraw_penalty_bounty` | `bounty_id`, `hunter`, `stake_returned`, `penalty_received` |
| `RemainingWithdrawn` | `withdraw_remaining_bounty` | `bounty_id`, `creator`, `escrow_returned`, `stakes_returned` |
| `BountyExpired` | `expire_bounty` | `bounty_id`, `caller`, `cleanup_reward`, `refund_to_creator`, `forfeited_stakes` |
| `BountyAbandoned` | `abandon_bounty` | `bounty_id`, `ticket_id`, `hunter`, `forfeited_stake` |
| `TicketDestroyed` | `destroy_ticket_bounty` | `bounty_id`, `ticket_id` |
| `VerifierCapDestroyed` | `destroy_verifier_cap_bounty` | `bounty_id`, `cap_id` |

### Indexer Event Subscription

```typescript
import { SuiClient } from "@mysten/sui/client";

const client = new SuiClient({ url: "https://fullnode.testnet.sui.io:443" });
const BOUNTY_PKG = "0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16";

// 查詢特定 Bounty 的所有 events
async function getBountyEvents(bountyId: string) {
  const events = await client.queryEvents({
    query: {
      MoveEventModule: {
        package: BOUNTY_PKG,
        module: "bounty",
      },
    },
    limit: 50,
    order: "ascending",
  });

  // 過濾特定 bounty
  return events.data.filter(
    (e) => (e.parsedJson as any)?.bounty_id === bountyId
  );
}

// 即時監聽新建 Bounty
async function subscribeBountyCreated(callback: (event: any) => void) {
  const unsubscribe = await client.subscribeEvent({
    filter: {
      MoveEventType: `${BOUNTY_PKG}::bounty::BountyCreated`,
    },
    onMessage: callback,
  });
  return unsubscribe;
}
```

### 各場景建議監聽的 Events

| 場景 | 角色 | 監聽 |
|------|------|------|
| Intel Bounty | Explorer Hub Frontend | `BountyCreated` (新懸賞), `BountyApproved` (驗收通知) |
| Intel Bounty | Intel Verifier Bot | `BountyClaimed` (觸發品質檢查) |
| PvP Bounty | Fleet Command UI | `BountyCreated`, `BountyClaimed`, `BountyAbandoned` |
| PvP Bounty | Battle Judge | `BountyClaimed` (啟動戰鬥監控) |
| Logistics | DAO Dashboard | `BountyCreated`, `BountyClaimed`, `RewardClaimed` |
| Logistics | Runner App | `BountyCreated` (新任務), `BountyApproved` (可領錢) |
| All | Cleanup Bots | `BountyExpired` (cleanup reward 機會) |

---

## §8 — Upgrade & Migration Notes

### Version 欄位

`Bounty<T>.version` 目前固定為 `1`（`constants::current_version()`）。升級合約時：

1. 新版 package 會有新的 package ID
2. 已建立的 `Bounty<T>` objects 仍指向舊 package
3. 新功能透過 `version` 欄位做 gate：`assert!(bounty.version >= REQUIRED_VERSION)`

### 對上層合約的影響

| 升級類型 | 影響 | 上層需要做什麼 |
|----------|------|---------------|
| **Bug fix**（compatible） | 無 — 既有 public fun 簽名不變 | 更新 Move.toml dependency rev |
| **新增 function** | 無 — additive change | 選擇性使用新 API |
| **修改 struct layout** | ⚠️ 需 migration | 等 migration tx 完成後更新 dependency |
| **刪除 public fun** | ❌ 不允許（Move upgrade policy） | N/A |

### Move.toml 升級流程

```toml
# 升級前
BountyEscrow = { id = "0x8222...cb16", version = 1 }

# 升級後（新 version publish 後）
BountyEscrow = { id = "0x8222...cb16", version = 2 }
```

### 建議

- 上層合約 **不要硬編碼** Bounty package ID — 用 `Move.toml` dependency 管理
- 使用 `bounty::status()` accessor 而非直接比對數字 — 未來可能新增狀態
- 監聽 `BountyCreated.coin_type` 欄位過濾 — 支援非 SUI token 的場景
