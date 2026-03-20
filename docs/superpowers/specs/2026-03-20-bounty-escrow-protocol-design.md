# Bounty Escrow Protocol — System Design Spec

> Status: Reviewed (architect + security + red-team)
> Date: 2026-03-20
> Scope: Sui Move smart contract — 底層懸賞任務與資金託管協議

---

## 1. Overview

Bounty Escrow Protocol 是 EVE Frontier 生態的底層基礎設施合約，提供無信任的鏈上懸賞任務發布、資金託管、驗證與自動撥款機制。被三個上層應用共用：

- **Frontier Explorer Hub** → 情報懸賞
- **Fleet Command Doctrine** → 戰鬥合約
- **Tribal Governance DAO** → 後勤任務

**核心流程**：發布懸賞 → 鎖定資金 → 接取任務（質押）→ 驗收通過 → 請款領獎

### 設計哲學：Game-as-Reality

EVE Frontier 的世界觀反映現實世界中實際會發生的情境。協議的每個機制都對應真實商業行為：

| 協議機制 | 現實世界對應 |
|---|---|
| Two-step verify（approve → claim_reward） | 甲方驗收通過 → 乙方開發票請款 |
| Grace period | 合約法的補救期 — 逾期但工作完成，仍應付款 |
| Withdrawal pattern（cancel 後 hunter 自行領款） | 公司宣布取消合約 → 承包商各自去法務部領違約金 |
| Cleanup reward | 拾荒者經濟 — 有人清理廢棄任務就給報酬 |
| Hunter stake（保證金） | 履約保證金 — 接案先押錢，擺爛沒收 |
| MIN_DEADLINE_DURATION | 勞動法最低公告期 — 不能發一秒假工作騙保證金 |
| abandon（主動棄單） | 承包商主動解約，保證金沒收 |

---

## 2. Design Decisions

| 決策項 | 選擇 | 理由 |
|---|---|---|
| 驗證機制 | 混合模式（Verifier 接口） | 不同任務類型插入不同驗證策略（發布者確認、多簽、Oracle） |
| 驗證流程 | Two-step：approve + claim_reward | 映射現實「驗收→請款」；解決 Sui owned-object 限制（verifier 無法存取 hunter 的 ticket） |
| 物件模型 | Shared Bounty + Owned ClaimTicket + Owned VerifierCap | 公開任務板 + 接取者所有權證明 + 驗證者能力憑證 |
| 代幣類型 | 泛型 `Coin<T>` | 低成本支持任意代幣，為 EVE 遊戲代幣預留 |
| 超時機制 | Deadline + Grace Period + 任何人觸發清算 + cleanup reward | 符合 EVE「沒有免費午餐」世界觀 |
| Cancel 模式 | Withdrawal pattern（標記→各自領款） | 映射現實「公告→申報債權」；解決 100 人 cancel gas 問題 |
| 上層整合 | 純通用 Protocol + `public fun` 版本 | `entry` 給 CLI/wallet，`public fun` 給上層合約組合呼叫 |
| Hunter 質押 | 雙向質押博弈 | 防止 hunter 佔坑不做事，防止 creator 擅自取消 |
| Stake 存放 | 集中存放在 Bounty（stake_pool） | Sui owned-object 無法被第三方操作，集中存放確保 cancel/expire 正確分帳 |
| 不可變性 | Bounty 創建後不可修改 | 確保 trustlessness — hunter 接單時看到的條件即最終條件 |
| 無 store ability | Bounty/ClaimTicket 只有 key | 防止被 wrap 進其他 object 造成預期外的所有權轉移 |
| 升級策略 | 保留 UpgradeCap + compatible policy | 預留升級彈性，version 欄位支持未來遷移 |

---

## 3. Object Model

### Bounty\<T\> (Shared Object)

```
struct Bounty<phantom T> has key {
    id: UID,
    version: u64,                 // 版本欄位，支持未來升級遷移
    creator: address,
    title: String,
    description: String,
    // --- 資金池 ---
    escrow: Balance<T>,           // 獎勵資金池
    stake_pool: Balance<T>,       // hunter 質押集中存放
    // --- 參數 ---
    reward_amount: u64,           // 每人獎勵金額
    required_stake: u64,          // hunter 接單質押門檻
    cleanup_reward_bps: u16,      // 清算獎勵 basis points (e.g. 100 = 1%)
    deadline: u64,                // 過期時間 (timestamp ms)
    grace_period: u64,            // 驗收補救期 (ms)，deadline 後仍可 approve
    // --- 狀態 ---
    status: u8,                   // Open/Claimed/Completed/Cancelled/Expired
    max_claims: u64,
    active_claims: u64,           // 當前有效 claim 數（未 approve/abandon 的）
    completed_claims: u64,        // 已 approve 完成的數量
    claimed_hunters: VecSet<address>,          // 防止重複 claim（含已完成/放棄的，永不移除）
    active_hunter_stakes: VecMap<address, u64>, // 當前 active hunters 及其質押金額
    approved_hunters: VecSet<address>,          // 已被 approve 但尚未 claim_reward 的 hunters
    // --- 擴展 ---
    metadata: VecMap<String, String>,
}
```

### ClaimTicket (Owned Object) — 輕量憑證，不持有資金

```
struct ClaimTicket has key {
    id: UID,
    bounty_id: ID,
    hunter: address,
    stake_amount: u64,            // 記錄質押金額（實際資金在 Bounty.stake_pool）
    claimed_at: u64,
}
```

### VerifierCap (Owned Object)

```
struct VerifierCap has key {
    id: UID,
    bounty_id: ID,
}
```

**關鍵設計點**：

- **`version: u64`**：初始值 1，未來升級時用來區分新舊 Bounty 物件，支持 migration 邏輯
- **Stake 集中存放**：hunter 質押存入 `Bounty.stake_pool`，解決 Sui owned-object 無法被第三方操作的限制
- **`stake_pool` 動態餘額**：隨 approve（退還 stake）和 abandon（沒收轉出）而減少，expire 時只包含未解決的 active hunters 質押
- **`active_hunter_stakes: VecMap<address, u64>`**：追蹤 active hunters 及其質押。approve/abandon 時移除 entry
- **`approved_hunters: VecSet<address>`**：two-step verify 中間狀態 — verifier approve 後、hunter claim_reward 前
- **`claimed_hunters`**：包含所有曾 claim 過的地址（含已完成/放棄），永不移除，可能超過 `max_claims`（因為 abandon 循環）
- **`ClaimTicket`**：純憑證（只有 `key`，無 `store`），不持有 Balance。approve 不消耗它，claim_reward 時消耗（by value）
- **`VerifierCap`**：只能由 `create` 內部 mint，外部無法偽造。驗證者可以是合約地址（支持 Oracle/多簽等上層邏輯）

---

## 4. State Machine

### 狀態定義

| 狀態 | 條件 | 說明 |
|---|---|---|
| **Open** | `active_claims < max_claims` | 可被 claim，可能已有部分 claim 進行中 |
| **Claimed** | `active_claims == max_claims` | 所有名額已滿，等待驗證 |
| **Completed** | 所有 claims 已解決 (approve+claim_reward / abandon) 且 `completed_claims > 0` | 任務成功完結 |
| **Cancelled** | creator 主動取消 | 標記取消，hunters 各自 withdraw |
| **Expired** | deadline + grace_period 已過且未全部完成 | 清算完畢 |

**終態 (Terminal States)**：Completed、Cancelled、Expired。終態後無任何狀態轉換。

### 時間軸

```
|── bounty active ──|── grace period（可 approve，不可 expire）──|── 可 expire ──|
                 deadline                              deadline + grace_period
```

- **deadline 前**：所有操作正常（claim, approve, abandon, cancel）
- **deadline ~ deadline+grace_period**：不可 claim / 不可 expire / 可 approve + claim_reward / 不可 abandon（強制走 expire）
- **deadline+grace_period 後**：只能 expire

### 轉換規則與資金流向

| 從 | 到 | 觸發 | 誰能呼叫 | 資金流向 |
|---|---|---|---|---|
| Open | Open/Claimed | `claim()` | 任何人 | hunter 的 stake → stake_pool；滿額轉 Claimed |
| Open/Claimed | — | `approve()` | VerifierCap 持有者 | 無資金移動，標記 hunter 進 approved_hunters |
| Open/Claimed | Open/Completed | `claim_reward()` | approved hunter | reward (escrow→hunter) + stake (stake_pool→hunter)；銷毀 ticket |
| Open/Claimed | Open | `abandon()` | ticket owner（deadline 前） | stake (stake_pool→creator)；銷毀 ticket |
| Open | Cancelled | `cancel()` | creator（無 active claims） | escrow 全額 → creator |
| Open/Claimed | Cancelled | `cancel()` | creator（有 active claims） | 標記 Cancelled；資金不立即分配 |
| Cancelled | — | `withdraw_penalty()` | active hunter | stake + 違約金 → hunter |
| Cancelled | — | `withdraw_remaining()` | creator | escrow 餘額 + stake_pool 餘額 → creator（所有 hunter 領完後） |
| Open/Claimed | Expired | `expire()` | 任何人（deadline+grace_period 後） | stake_pool → creator；cleanup_reward → caller；escrow 餘額 → creator |

### 違約金規則（Cancel with active claims）

Creator cancel 已有 active claims 的 Bounty 時，進入 **Cancelled + Withdrawal** 模式：
1. `cancel()` 只標記狀態為 Cancelled，不分帳
2. 每位 active hunter 呼叫 `withdraw_penalty()` 領取：自己的 stake + `required_stake`（違約金，從 escrow 扣）
3. 所有 hunter 領完後，creator 呼叫 `withdraw_remaining()` 領回餘額
4. 若 escrow 不足支付所有違約金，cancel 直接 abort（`E_INSUFFICIENT_ESCROW_FOR_PENALTY`），creator 只能等 expire

**為何用 Withdrawal Pattern**：
- 現實映射：公司宣布取消合約 → 承包商各自去法務部領違約金
- 技術優勢：避免單筆 tx 遍歷 100 個 hunter 造成 gas 爆炸
- 責任分離：每個 hunter 為自己的提款負責 gas 費

### 多人 claim 詳細規則

- `claim()` 後若 `active_claims < max_claims`，保持 **Open**
- `claim()` 後若 `active_claims == max_claims`，轉 **Claimed**
- `abandon()` 後若 `active_claims` 降回 `< max_claims`，回到 **Open**
- `claim_reward()` 後若所有 claims 已解決（`active_claims == 0`）且 `completed_claims > 0`，轉 **Completed**
- `claim_reward()` 後若仍有 active claims，狀態不變
- 部分完成後 `expire()`：已完成的 hunter 獎勵不受影響（已發出），未完成 hunter 的 stake 沒收歸 creator
- `claimed_hunters` 可能超過 `max_claims`（abandon 循環產生新 claimers），這是預期行為

---

## 5. Module Architecture

```
bounty_escrow/
├── sources/
│   ├── bounty.move          ← 核心：狀態機 + public fun + entry fun
│   ├── escrow.move          ← 資金託管：鎖定、釋放、分帳
│   ├── verifier.move        ← VerifierCap 創建與權限檢查
│   ├── constants.move       ← 狀態碼、上限、預設值、錯誤碼
│   └── display.move         ← Publisher + Display V2 註冊
├── tests/
│   ├── test_create.move
│   ├── test_claim.move
│   ├── test_approve_claim.move
│   ├── test_cancel_withdraw.move
│   ├── test_expire.move
│   ├── test_abandon.move
│   └── test_monkey.move
└── Move.toml
```

### Entry Functions + Public Fun (bounty.move)

每個 entry function 都有對應的 `public fun` 版本供上層合約組合呼叫。
entry 版本做 implicit transfer；public fun 版本回傳物件讓 caller 自行處理。

```
// === 發布者操作 ===
public fun create<T>(...) : (Bounty<T>, VerifierCap)
public entry fun create<T>(
    title: String, description: String, coin: Coin<T>,
    reward_amount: u64, required_stake: u64, max_claims: u64,
    deadline: u64, grace_period: u64, cleanup_reward_bps: u16,
    verifier: address,
    clock: &Clock, ctx: &mut TxContext
)

public entry fun cancel<T>(
    bounty: &mut Bounty<T>, clock: &Clock, ctx: &mut TxContext
)
// Open（無 active claims）：escrow 全額退 creator
// Open/Claimed（有 active claims）：標記 Cancelled，進入 withdrawal 模式

// === Hunter 操作 ===
public entry fun claim<T>(
    bounty: &mut Bounty<T>, stake_coin: Coin<T>,
    clock: &Clock, ctx: &mut TxContext
)
// 質押存入 stake_pool，mint ClaimTicket 給 hunter

public entry fun claim_reward<T>(
    bounty: &mut Bounty<T>, ticket: ClaimTicket,
    ctx: &mut TxContext
)
// hunter 已被 approve → 從 escrow 領 reward + 從 stake_pool 領回 stake，銷毀 ticket

public entry fun abandon<T>(
    bounty: &mut Bounty<T>, ticket: ClaimTicket,
    clock: &Clock, ctx: &mut TxContext
)
// deadline 前：stake 沒收 → creator，銷毀 ticket
// deadline 後：禁止 abandon，強制走 expire

public entry fun withdraw_penalty<T>(
    bounty: &mut Bounty<T>, ticket: ClaimTicket,
    ctx: &mut TxContext
)
// Cancelled 狀態：hunter 領回 stake + 違約金，銷毀 ticket

public entry fun withdraw_remaining<T>(
    bounty: &mut Bounty<T>, ctx: &mut TxContext
)
// Cancelled 狀態 + 所有 hunter 已 withdraw：creator 領回餘額

// === 驗證者操作 ===
public entry fun approve<T>(
    bounty: &mut Bounty<T>, hunter: address,
    cap: &VerifierCap, clock: &Clock, ctx: &mut TxContext
)
// 標記 hunter 為 approved（不需要 hunter 的 ticket）
// 可在 deadline + grace_period 內呼叫

// === 公開操作 ===
public entry fun expire<T>(
    bounty: &mut Bounty<T>, clock: &Clock, ctx: &mut TxContext
)
// deadline + grace_period 過後任何人可呼叫
// stake_pool → creator，cleanup_reward → caller，escrow 餘額 → creator

// === 清理操作 ===
public entry fun destroy_ticket<T>(
    ticket: ClaimTicket, bounty: &Bounty<T>
)
// 終態時銷毀孤兒 ClaimTicket；需檢查 ticket.bounty_id == bounty.id

public entry fun destroy_verifier_cap<T>(
    cap: VerifierCap, bounty: &Bounty<T>
)
// 終態時銷毀 VerifierCap
```

### display.move — Publisher + Display V2

```
fun init(otw: BOUNTY_ESCROW, ctx: &mut TxContext) {
    // 1. claim Publisher
    let publisher = package::claim(otw, ctx);

    // 2. register Display V2 for Bounty<T>, ClaimTicket, VerifierCap
    //    Bounty: title, reward_amount, status, deadline
    //    ClaimTicket: bounty_id, hunter, stake_amount
    //    VerifierCap: bounty_id

    // 3. transfer Publisher to sender (or DAO multisig)
}
```

### escrow.move (package-internal)

```
public(package) fun lock<T>(balance: &mut Balance<T>, coin: Coin<T>, amount: u64)
public(package) fun release_to<T>(balance: &mut Balance<T>, amount: u64, recipient: address, ctx: &mut TxContext)
public(package) fun release_all<T>(balance: &mut Balance<T>, recipient: address, ctx: &mut TxContext)
public(package) fun calculate_cleanup_reward(total: u64, bps: u16): u64
    // 用 u128 中間運算避免溢出: (total as u128) * (bps as u128) / 10000
    // 最小值: if bps > 0 && total > 0 then max(result, 1) else 0
public(package) fun transfer_between<T>(from: &mut Balance<T>, to: &mut Balance<T>, amount: u64)
```

### verifier.move (package-internal)

```
public(package) fun issue_cap(bounty_id: ID, verifier: address, ctx: &mut TxContext)
public(package) fun validate_cap(cap: &VerifierCap, bounty_id: ID)
```

### constants.move

```
// === 狀態碼 ===
const STATUS_OPEN: u8 = 0;
const STATUS_CLAIMED: u8 = 1;
const STATUS_COMPLETED: u8 = 2;
const STATUS_CANCELLED: u8 = 3;
const STATUS_EXPIRED: u8 = 4;

// === 上限 ===
const MAX_CLEANUP_REWARD_BPS: u16 = 1000;   // 10%
const MAX_CLAIMS: u64 = 100;                // 防止 VecSet/VecMap gas 爆炸
const MAX_TITLE_LENGTH: u64 = 256;
const MAX_DESCRIPTION_LENGTH: u64 = 2048;
const MAX_METADATA_ENTRIES: u64 = 20;
const MAX_METADATA_VALUE_LENGTH: u64 = 1024;
const MIN_DEADLINE_DURATION: u64 = 3_600_000;  // 最少 1 小時
const MAX_DEADLINE_DURATION: u64 = 31_536_000_000;  // 最多 365 天
const DEFAULT_GRACE_PERIOD: u64 = 86_400_000; // 預設 24 小時
const CURRENT_VERSION: u64 = 1;

// === 錯誤碼 ===
const E_INSUFFICIENT_ESCROW: u64 = 0;
const E_DEADLINE_TOO_SOON: u64 = 1;
const E_DEADLINE_TOO_FAR: u64 = 2;
const E_CLEANUP_BPS_TOO_HIGH: u64 = 3;
const E_TITLE_TOO_LONG: u64 = 4;
const E_TITLE_EMPTY: u64 = 5;
const E_DESCRIPTION_TOO_LONG: u64 = 6;
const E_BOUNTY_NOT_OPEN: u64 = 7;
const E_MAX_CLAIMS_REACHED: u64 = 8;
const E_INSUFFICIENT_STAKE: u64 = 9;
const E_DEADLINE_PASSED: u64 = 10;
const E_CREATOR_CANNOT_CLAIM: u64 = 11;
const E_ALREADY_CLAIMED: u64 = 12;
const E_NOT_CREATOR: u64 = 13;
const E_BOUNTY_NOT_CANCELLABLE: u64 = 14;
const E_INSUFFICIENT_ESCROW_FOR_PENALTY: u64 = 15;
const E_INVALID_VERIFIER_CAP: u64 = 16;
const E_HUNTER_NOT_ACTIVE: u64 = 17;
const E_INSUFFICIENT_ESCROW_FOR_REWARD: u64 = 18;
const E_NOT_TICKET_OWNER: u64 = 19;
const E_GRACE_PERIOD_NOT_PASSED: u64 = 20;
const E_BOUNTY_NOT_ACTIVE: u64 = 21;
const E_MAX_CLAIMS_ZERO: u64 = 22;
const E_REWARD_AMOUNT_ZERO: u64 = 23;
const E_MAX_CLAIMS_TOO_HIGH: u64 = 24;
const E_BOUNTY_NOT_TERMINAL: u64 = 25;
const E_TICKET_BOUNTY_MISMATCH: u64 = 26;
const E_HUNTER_NOT_APPROVED: u64 = 27;
const E_BOUNTY_NOT_CANCELLED: u64 = 28;
const E_HUNTERS_NOT_WITHDRAWN: u64 = 29;
const E_ABANDON_AFTER_DEADLINE: u64 = 30;
const E_TOO_MANY_METADATA: u64 = 31;
const E_METADATA_VALUE_TOO_LONG: u64 = 32;
const E_ALREADY_APPROVED: u64 = 33;
const E_OVERFLOW: u64 = 34;
```

---

## 6. Events

```
struct BountyCreated has copy, drop {
    bounty_id: ID,
    creator: address,
    coin_type: String,            // type_name::get<T>() 供 indexer 過濾
    reward_amount: u64,
    required_stake: u64,
    max_claims: u64,
    deadline: u64,
    grace_period: u64,
    verifier: address,
}

struct BountyClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    stake_amount: u64,
}

struct BountyApproved has copy, drop {
    bounty_id: ID,
    hunter: address,
    verifier: address,            // 哪個 verifier approve 的
}

struct RewardClaimed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    reward_amount: u64,
    stake_returned: u64,
}

struct BountyCancelled has copy, drop {
    bounty_id: ID,
    creator: address,
    active_claims_at_cancel: u64,
    penalty_per_hunter: u64,      // 0 if no active claims
}

struct PenaltyWithdrawn has copy, drop {
    bounty_id: ID,
    hunter: address,
    stake_returned: u64,
    penalty_received: u64,
}

struct RemainingWithdrawn has copy, drop {
    bounty_id: ID,
    creator: address,
    escrow_returned: u64,
    stakes_returned: u64,
}

struct BountyExpired has copy, drop {
    bounty_id: ID,
    caller: address,
    cleanup_reward: u64,
    refund_to_creator: u64,
    forfeited_stakes: u64,
}

struct BountyAbandoned has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
    hunter: address,
    forfeited_stake: u64,
}

struct TicketDestroyed has copy, drop {
    bounty_id: ID,
    ticket_id: ID,
}

struct VerifierCapDestroyed has copy, drop {
    bounty_id: ID,
    cap_id: ID,
}
```

---

## 7. Security Model

### Per-Function Checks

| Function | 檢查項 |
|---|---|
| `create()` | coin ≥ reward_amount × max_claims（u128 檢查溢出）；deadline ≥ now + MIN_DEADLINE_DURATION；deadline ≤ now + MAX_DEADLINE_DURATION；bps ≤ MAX；title 長度 1..256；desc ≤ 2048；max_claims 1..100；reward > 0；metadata entries ≤ 20 |
| `claim()` | status ∈ {Open}；active_claims < max_claims；stake ≥ required_stake；now < deadline；caller ≠ creator；caller ∉ claimed_hunters |
| `approve()` | status ∈ {Open, Claimed}；cap.bounty_id == bounty.id；hunter ∈ active_hunter_stakes；hunter ∉ approved_hunters；now ≤ deadline + grace_period |
| `claim_reward()` | hunter ∈ approved_hunters；ticket.bounty_id == bounty.id；ticket.hunter == caller；escrow ≥ reward_amount |
| `cancel()` | caller == creator；status ∈ {Open, Claimed}；若有 active claims，escrow ≥ required_stake × active_claims |
| `withdraw_penalty()` | status == Cancelled；ticket.bounty_id == bounty.id；ticket.hunter == caller；hunter ∈ active_hunter_stakes |
| `withdraw_remaining()` | status == Cancelled；caller == creator；active_hunter_stakes 為空（所有 hunter 已 withdraw） |
| `abandon()` | ticket.hunter == caller；status ∈ {Open, Claimed}；now < deadline |
| `expire()` | now > deadline + grace_period；status ∈ {Open, Claimed} |
| `destroy_ticket()` | status ∈ terminal；ticket.bounty_id == bounty.id |
| `destroy_verifier_cap()` | status ∈ terminal；cap.bounty_id == bounty.id |

### Red Team Attack Vectors

| # | 攻擊 | 防禦 |
|---|---|---|
| 1 | 重複 claim 佔滿名額 | `claimed_hunters: VecSet` 鏈上強制 |
| 2 | 偽造 VerifierCap | `issue_cap` 是 `public(package)` |
| 3 | 重複 approve 同一 hunter | `approved_hunters` VecSet 檢查 |
| 4 | 傳入假 Clock | Sui 系統 Clock `0x6` 無法偽造 |
| 5 | Cancel 搶跑 verify | Sui object-centric 排序消除 front-running |
| 6 | 整數溢出（reward × max_claims） | u128 中間運算 + `E_OVERFLOW` |
| 7 | `calculate_cleanup_reward` 溢出 | u128 中間運算 |
| 8 | 超短 deadline 偷 stake | `MIN_DEADLINE_DURATION` = 1 小時 |
| 9 | 超長 deadline 永鎖資金 | `MAX_DEADLINE_DURATION` = 365 天 |
| 10 | Deadline 後 abandon 繞過 expire | abandon 禁止在 deadline 後呼叫 |
| 11 | Cancel 100 人 gas 爆炸 | Withdrawal pattern，每人自行提款 |
| 12 | Metadata 灌爆 storage | `MAX_METADATA_ENTRIES` = 20 |
| 13 | 空 title spam | `E_TITLE_EMPTY` 檢查 |

### Design-Level Security Choices

- **無 `store` ability**：防止 wrap 攻擊
- **不可變參數**：hunter 接單條件即最終條件
- **Stake 集中管理**：合約對資金有完全控制權
- **Grace period**：防止 verify/expire 競態，給 hunter 公平的驗收窗口
- **Withdrawal pattern**：責任分離 + gas 安全

### Trust Assumptions（已知限制，文件記錄）

以下問題在鏈上無法完全防範，屬於協議的信任假設：

1. **Sybil 攻擊**：Creator 可用第二個地址 claim 自己的 bounty。`caller ≠ creator` 只防一層。上層應用可加入聲譽系統
2. **Creator-Verifier 共謀**：若 verifier 是 creator 指定的，兩者可以共謀 approve 未完成工作。上層應選用可信的多簽或 Oracle 作為 verifier
3. **Cleanup reward 自我交易**：Creator 可自行 expire 並從另一地址領 cleanup reward。淨損失 = 0（減 gas），但會產生鏈上垃圾
4. **零質押 bounty**：`required_stake = 0` 時 hunter 無保障。協議允許此設定，但 creator 自擔風險

---

## 8. Upgrade Strategy

### 原則

- **保留 `UpgradeCap`**：部署時不 burn，存放在安全地址（建議 DAO multisig）
- **Compatible policy**：只做 compatible 升級（可加新 field/function，不可刪改既有）
- **`version` 欄位**：Bounty struct 包含 `version: u64`，升級後新邏輯可透過 version 區分新舊物件
- **Error codes 是公開 API**：常數值不可在升級中變更，上層合約可能硬編碼這些值
- **Display 可升級**：Display V2 metadata 可透過 Publisher 更新，不需要合約升級

### 未來擴展方向（不在 v1 實作）

- 多 verifier（mint 多個 VerifierCap）
- Verifier delegation（transfer_verifier_cap）
- Bounty 模板（常用配置的 factory function）
- 鏈上聲譽系統（hunter 完成率追蹤）

---

## 9. Testing Strategy

### Unit Tests

| 測試檔 | 覆蓋 |
|---|---|
| `test_create.move` | 正常創建、金額不足、deadline 太短/太長、空 title、超長 title、bps 超限、max_claims=0/101、reward=0、metadata 超限 |
| `test_claim.move` | 正常 claim、質押不足、重複 claim、超 max_claims、creator 不能 claim 自己、deadline 已過 |
| `test_approve_claim.move` | 正常 approve→claim_reward 全流程、假 cap、hunter 不在 active 列表、重複 approve、grace period 內 approve、grace period 後 approve 失敗、escrow 不足 |
| `test_cancel_withdraw.move` | Open 無 claim 取消（直接退款）、有 claim 取消→withdraw_penalty→withdraw_remaining 全流程、非 creator 不能 cancel、escrow 不足付違約金、hunter 未全部 withdraw 時 creator 不能 withdraw_remaining |
| `test_expire.move` | Open 無 claim 過期 + cleanup reward、Claimed 過期 + stake 沒收、grace period 內不能 expire、grace period 後正常 expire |
| `test_abandon.move` | 正常放棄 + stake 沒收、非 owner 不能 abandon、abandon 後 Claimed→Open、deadline 後不能 abandon |

### Monkey Tests (`test_monkey.move`)

| 場景 | 目的 |
|---|---|
| max_claims = 100 全 claim 後全 abandon | VecSet/VecMap 壓力 |
| reward_amount = 1 | 整數除法 / cleanup reward 最小值 = 1 |
| required_stake = 0 | 零質押全流程正常 |
| deadline = now + MIN_DEADLINE_DURATION | 最短 deadline |
| cleanup_reward_bps = 0 | 無清算獎勵的 expire |
| coin > 所需金額 | 找零退回 creator |
| cancel 後再 cancel | 已取消不能重複 |
| expire 後再 expire | 已過期不能重複 |
| `calculate_cleanup_reward(u64::MAX, 1000)` | u128 溢出防護 |
| 5 claim + 5 abandon + 5 新 claim | claimed_hunters 超過 max_claims |
| approve 後 hunter 不領獎 → expire | approved 但未 claim_reward 的處理 |

### Integration Tests

| 場景 | 流程 |
|---|---|
| Happy path | create → claim → approve → claim_reward → hunter 收到 reward + stake |
| Creator 違約 | create → claim → cancel → withdraw_penalty → withdraw_remaining |
| Hunter 擺爛 | create → claim → (deadline+grace) → expire → caller 收到 cleanup reward |
| 多人部分完成 | create(max=3) → 3x claim → 1x approve+claim_reward → 1x abandon → expire |
| 零質押 bounty | create(stake=0) → claim → approve → claim_reward |
| 滿額後 abandon 重開 | create(max=1) → claim → abandon → 新 hunter claim → approve → claim_reward |
| Grace period 驗收 | create → claim → (deadline 過) → approve(grace 內) → claim_reward |
| 孤兒清理 | create → claim → expire → destroy_ticket + destroy_verifier_cap |
| Cancel escrow 不足 | create(stake > reward) → claim → approve+claim_reward(部分) → cancel abort |
