# 專案名稱：Bounty_Escrow_Protocol (星際賞金與任務託管協議)

> 📜 **[EVE Frontier 專案憲法與開發準則](https://github.com/Eve-Frontier-Changsha-2026/Constitution/blob/master/EVE_Frontier_Project_Constitution.md)**
> 本專案的世界觀設定與底層相依資源，均遵從此憲法文檔之規範。

## 📌 概念簡介
這是一個貫穿 EVE Frontier 生態系的「底層懸賞智能合約協議」。它將原本分散的玩家需求（如收集情報、獵殺海盜、運輸物資）標準化為鏈上可驗證的任務 (Bounty)。透過自動化的資金託管 (Escrow) 系統，任何人或 DAO 皆可發布無信任 (Trustless) 的懸賞任務，完成條件後自動撥款。

## 🎯 解決痛點與核心循環
- **去中心化任務板 (Decentralized Bounty Board)**：玩家可抵押一定代幣發布任務，避免了傳統 MMO 中「拿錢不辦事」或「辦事不給錢」的詐騙風險。
- **跨專案通用架構**：這不只是一個單獨的 App，而是一個被其他系統廣泛呼叫的 Protocol。無論是情報網、指揮部還是部落治理，都可以將其特定的需求轉化為一筆 Bounty。
- **事件驅動的驗證機制 (Event-driven Verification)**：透過讀取 EVE Frontier 鏈上的事件日誌（如 Killmail、Smart Storage 的轉移紀錄、礦物提交紀錄），智能合約可自動判定任務是否達成，無需人工介入審核。

## 🔗 與其他專案的整合參考
此協議將作為底下三大應用層的底層金流與任務引擎：
- **[Frontier_Explorer_Hub](../Frontier_Explorer_Hub)**：用於發布「情報懸賞」(Bounty for Intel) —— 尋求特定星系的探勘報告或熱力圖數據。
- **[Fleet_Command_Doctrine](../Fleet_Command_Doctrine)**：用於發布「戰鬥合約」(Bounty for PvP) —— 將獵殺令或防守設施的傭兵任務上鏈，擊殺自動結算。
- **[Tribal_Governance_DAO](../Tribal_Governance_DAO)**：用於發布「後勤任務」(Bounty for Logistics) —— 國庫自動提撥資金，下達採集或運輸物資到前線基地的生產指令。

## 🏆 得獎潛力
- **Toolkit for Civilization**：從單一應用提升到基礎設施（Infrastructure）的高度，完美展示了 Web3 可組合性 (Composability)。
- **打通經濟命脈**：把「情報、戰鬥、後勤」這三個原本獨立的行為，用「資金分配」串成完整的商業閉環。
- **展現 Move 合約實力**：透過 Sui Move 合約處理複雜的條件鎖定、時間戳控制與多方資產託管，展示進階的練上技術。


## Specifications

### 2026 03 20 Bounty Escrow Protocol Design

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


### 2026 03 20 Red Team Report

# Red Team Report -- Bounty Escrow Protocol (Pre-Implementation)

> Date: 2026-03-20
> Type: Design-phase adversarial analysis (no code exists yet)
> Target: Bounty Escrow Protocol design spec
> Rounds: 8 categories + combo attacks = 32 attack vectors

---

## Summary

| Category | Vectors | EXPLOITED | SUSPICIOUS | DEFENDED |
|---|---|---|---|---|
| Access Control Bypass | 5 | 0 | 1 | 4 |
| Integer/Arithmetic Abuse | 5 | 1 | 2 | 2 |
| Object Manipulation | 4 | 0 | 1 | 3 |
| Economic Exploits | 6 | 2 | 2 | 2 |
| Input Fuzzing | 4 | 0 | 1 | 3 |
| Ordering Attacks | 3 | 0 | 1 | 2 |
| Type Confusion | 2 | 0 | 0 | 2 |
| DoS Vectors | 3 | 0 | 2 | 1 |

**Totals: 3 EXPLOITED / 10 SUSPICIOUS / 19 DEFENDED**

Confidence: 70% (32 vectors across all 8 categories + combo analysis)

---

## Category 1: Access Control Bypass

### 1.1 Non-creator calls cancel()

- **Attack**: Attacker calls `cancel()` on someone else's Bounty.
- **Expected**: Should abort with `E_NOT_CREATOR`.
- **Spec defense**: `cancel()` checks `caller == creator`. DEFENDED.
- **Recommendation**: None -- straightforward sender check.

### 1.2 Non-verifier calls verify()

- **Attack**: Random address calls `verify()` without a valid `VerifierCap`.
- **Expected**: Should abort. Attacker cannot produce a `VerifierCap` for this bounty.
- **Spec defense**: `verify()` requires `cap: &VerifierCap` as parameter + `validate_cap(cap, bounty.id)`. `VerifierCap` is only minted inside `create()` via `public(package) fun issue_cap()`. DEFENDED.
- **Recommendation**: None.

### 1.3 Forge VerifierCap from another package

- **Attack**: Attacker deploys their own package that creates a struct also named `VerifierCap` and passes it to `verify()`.
- **Expected**: Move type system rejects at transaction level -- different module origin = different type.
- **Spec defense**: Sui Move type identity includes package address. DEFENDED.
- **Recommendation**: None.

### 1.4 Claim with a ClaimTicket from a different bounty

- **Attack**: Hunter has a valid `ClaimTicket` for bounty A, passes it to `verify()` targeting bounty B.
- **Expected**: Should abort with `E_TICKET_BOUNTY_MISMATCH`.
- **Spec defense**: `verify()` checks `ticket.bounty_id == bounty.id`. DEFENDED.
- **Recommendation**: None.

### 1.5 Creator claims own bounty via second address

- **Attack**: Creator uses a different address to claim their own bounty, then colludes with verifier.
- **Expected**: `claim()` blocks `caller == creator`, but not a second address controlled by the same person.
- **Spec defense**: Only blocks exact `creator` address. SUSPICIOUS -- sybil claims are not preventable on-chain.
- **Recommendation**: This is fundamentally unsolvable on-chain. Document as a known limitation. Upper-layer applications can add reputation systems or require identity verification. Consider adding a minimum `required_stake` enforcement at protocol level so sybil claiming at least costs capital.

---

## Category 2: Integer/Arithmetic Abuse

### 2.1 reward_amount * max_claims overflow

- **Attack**: Set `reward_amount = 2^63` and `max_claims = 3`. Product overflows u64.
- **Expected**: Should abort at `create()`.
- **Spec defense**: Spec says "create 時檢查乘法溢出" and Sui Move aborts on overflow. DEFENDED.
- **Recommendation**: Use explicit checked multiplication and abort with a clear error code (e.g., `E_OVERFLOW`). Do NOT rely solely on Move's implicit overflow abort -- the error message is unhelpful for debugging.

### 2.2 cleanup_reward rounding to zero, dust left in escrow

- **Attack**: Set `cleanup_reward_bps = 1` (0.01%) on a small escrow like 99 tokens. `calculate_cleanup_reward(99, 1) = 99 * 1 / 10000 = 0`. Cleanup caller gets 0 reward, no incentive to call `expire()`.
- **Expected**: `expire()` still works, caller just gets 0.
- **Spec defense**: None -- this is a design gap. EXPLOITED (economic, not security).
- **Recommendation**: Add a minimum cleanup reward floor (e.g., 1 unit) when `cleanup_reward_bps > 0` and escrow is non-zero. OR document that tiny bounties may have no cleanup incentive and rely on altruistic expiration.

### 2.3 required_stake = 0 with penalty calculation

- **Attack**: Creator sets `required_stake = 0`. Hunter claims for free. On cancel, penalty = `required_stake` = 0 per hunter. Hunter gets stake(0) + penalty(0) = nothing. Creator gets full escrow back.
- **Expected**: This is "working as designed" but it means zero-stake bounties give hunters zero protection against creator cancellation.
- **Spec defense**: Spec allows `required_stake = 0`. SUSPICIOUS.
- **Recommendation**: Document explicitly that `required_stake = 0` means hunters have no cancellation protection. Consider emitting a warning event or requiring a minimum stake. At minimum, the `abandon()` function should still work (forfeit 0 stake -- confirm no division by zero anywhere).

### 2.4 Penalty exhausts escrow, blocking cancel

- **Attack**: Create bounty with `reward_amount = 100`, `required_stake = 200`, `max_claims = 5`. Escrow = 500 (100*5). After 2 verifies, escrow = 300. Now cancel with 3 active claims needs penalty = 200*3 = 600 > 300. Cancel aborts.
- **Expected**: `E_INSUFFICIENT_ESCROW_FOR_PENALTY`. Creator stuck until expire.
- **Spec defense**: Spec acknowledges this scenario explicitly. DEFENDED (by design).
- **Recommendation**: The spec correctly identifies this. Ensure the error code is clear. Consider adding a `can_cancel()` view function so front-ends can check before attempting.

### 2.5 cleanup_reward_bps precision attack on large escrow

- **Attack**: `cleanup_reward_bps = 1000` (10%) on escrow of `u64::MAX`. `calculate_cleanup_reward(u64::MAX, 1000)` = `u64::MAX * 1000 / 10000`. The multiplication `u64::MAX * 1000` overflows u64.
- **Expected**: Should abort or be handled.
- **Spec defense**: No mention of overflow in `calculate_cleanup_reward`. SUSPICIOUS.
- **Recommendation**: Use `(total as u128) * (bps as u128) / 10000` to avoid intermediate overflow, then cast back to u64. This is a real bug if not handled.

---

## Category 3: Object Manipulation

### 3.1 Reuse consumed ClaimTicket

- **Attack**: After `verify()` consumes a ClaimTicket by value, try to use it again.
- **Expected**: Impossible -- Move's linear type system destroys the object.
- **Spec defense**: `verify()` and `abandon()` take `ticket: ClaimTicket` by value. DEFENDED.
- **Recommendation**: None -- Move enforces this at the language level.

### 3.2 Wrap Bounty object into another struct

- **Attack**: Wrap `Bounty<T>` inside another struct to manipulate access patterns.
- **Expected**: Impossible -- `Bounty` has `key` but no `store`, cannot be wrapped.
- **Spec defense**: Explicit design decision: "無 store ability". DEFENDED.
- **Recommendation**: None.

### 3.3 Use ClaimTicket from bounty A on bounty B for verify

- **Attack**: Pass a valid ticket (for bounty A) to `verify()` called on bounty B.
- **Expected**: Abort with `E_TICKET_BOUNTY_MISMATCH`.
- **Spec defense**: `verify()` checks `ticket.bounty_id == bounty.id`. DEFENDED.
- **Recommendation**: None.

### 3.4 Orphan ClaimTicket resource leak after cancel/expire

- **Attack**: After a bounty is cancelled/expired, hunters still hold their `ClaimTicket` objects. These are dead objects consuming storage.
- **Expected**: `destroy_ticket()` exists for cleanup, but requires hunter to call it.
- **Spec defense**: `destroy_ticket()` function exists. SUSPICIOUS -- relies on hunter cooperation for cleanup.
- **Recommendation**: Consider allowing anyone (not just the ticket owner) to call `destroy_ticket()` when the bounty is in a terminal state. The ticket has no value at that point, so there's no ownership concern. This enables third-party cleanup bots. Also consider whether `destroy_ticket` should give a small storage rebate incentive.

---

## Category 4: Economic Exploits

### 4.1 Creator griefing -- impossible conditions

- **Attack**: Creator sets `required_stake = u64::MAX - 1` (absurdly high) so no one can claim. Bounty sits idle. Creator waits for deadline, calls expire, gets full escrow back (minus cleanup reward to self).
- **Expected**: Creator can self-grief to recover escrow minus cleanup reward.
- **Spec defense**: None -- the protocol allows arbitrary parameters. SUSPICIOUS.
- **Recommendation**: Not a vulnerability per se (creator loses cleanup reward to whoever expires it, or loses nothing if they expire it themselves). But it could be used to spam the bounty board. Consider a minimum bounty creation fee or requiring `required_stake <= reward_amount` as a sanity check.

### 4.2 Creator cancels right before deadline

- **Attack**: Creator creates bounty, waits for hunters to claim and invest time, cancels 1 second before deadline. Hunters get stake + penalty back, but wasted effort.
- **Expected**: Hunters get compensated via penalty. The penalty = `required_stake` per hunter.
- **Spec defense**: Penalty mechanism exists. DEFENDED -- but only economically fair if penalty covers opportunity cost.
- **Recommendation**: The penalty design is sound. Document that `required_stake` should be set high enough to deter frivolous cancellation. Upper-layer apps can enforce minimum penalty ratios.

### 4.3 Hunter slot-squatting -- claim all slots with minimum stake, never complete

- **Attack**: Hunter (or sybil accounts) claims all `max_claims` slots. Never completes work. Holds bounty hostage until deadline.
- **Expected**: Hunters forfeit `required_stake` on expire. Creator gets stakes + remaining escrow.
- **Spec defense**: `required_stake` serves as anti-squatting mechanism. DEFENDED -- IF `required_stake` is set meaningfully.
- **Recommendation**: If `required_stake = 0`, this attack is free. Strongly recommend documenting that creators should set `required_stake > 0` to prevent squatting. Consider enforcing `required_stake > 0` at protocol level, or at least emitting a warning event.

### 4.4 Cleanup reward farming

- **Attack**: Attacker creates a bounty with `cleanup_reward_bps = 1000` (10%), deposits 1000 tokens, sets deadline = now + 1 second. Nobody claims. After 1 second, attacker (from another address) calls `expire()` and collects 100 tokens as cleanup reward. Creator address gets 900 back. Net cost to attacker: 0 (controls both addresses).
- **Expected**: Attacker controls both sides, so they pay themselves. Net economic effect: zero (minus gas).
- **Spec defense**: None explicitly. EXPLOITED -- but only for gas waste / bounty board spam.
- **Recommendation**: This is a self-dealing attack with no profit, but it pollutes the bounty board and wastes chain storage. Consider: (1) minimum bounty duration (e.g., 1 hour), (2) minimum escrow amount, (3) non-refundable creation fee. At minimum, document this as a known spam vector.

### 4.5 Collusion -- creator and verifier verify without work

- **Attack**: Creator sets `verifier = own_address_2`. Creates bounty. Sybil hunter claims. Verifier immediately verifies without checking work. Hunter gets reward + stake back.
- **Expected**: Protocol cannot distinguish legitimate verification from collusion.
- **Spec defense**: None -- this is by design (protocol is agnostic to verification logic). EXPLOITED (at the protocol level).
- **Recommendation**: This is inherent to any system with a single trusted verifier. The spec acknowledges this by making verification pluggable. Mitigations are upper-layer concerns: (1) multi-sig verifier, (2) oracle-based verification, (3) dispute period, (4) reputation system. Document this as an explicit trust assumption: "The protocol trusts that the verifier acts honestly. Collusion between creator and verifier is outside the protocol's threat model."

### 4.6 Abandon timing exploit

- **Attack**: Hunter claims, does the work, then calls `abandon()` instead of waiting for verify. Stake goes to creator. Then hunter submits work through a side channel and demands payment off-chain.
- **Expected**: Hunter loses stake. This is self-harming.
- **Spec defense**: Not really an attack. DEFENDED -- rational actors won't abandon completed work.
- **Recommendation**: None -- this is hunter self-sabotage.

---

## Category 5: Input Fuzzing

### 5.1 Empty title and description

- **Attack**: Call `create()` with `title = ""` and `description = ""`.
- **Expected**: Spec checks length <= MAX, but does not check length > 0.
- **Spec defense**: Only max-length checks exist. SUSPICIOUS.
- **Recommendation**: Add `E_TITLE_EMPTY` check. Empty bounties are likely spam. Enforce `title.length() > 0`.

### 5.2 max_claims = u64::MAX

- **Attack**: Set `max_claims = u64::MAX`. Then `reward_amount * max_claims` overflows.
- **Expected**: Overflow check at create catches this (if `reward_amount > 0`).
- **Spec defense**: Spec has `MAX_CLAIMS = 100` constant. DEFENDED.
- **Recommendation**: Ensure `create()` checks `max_claims <= MAX_CLAIMS` and aborts with `E_MAX_CLAIMS_TOO_HIGH`.

### 5.3 deadline = 0

- **Attack**: Set `deadline = 0` (epoch start).
- **Expected**: `deadline > now` check fails since `now` is always > 0.
- **Spec defense**: `create()` checks `deadline > now`. DEFENDED.
- **Recommendation**: None.

### 5.4 All metadata keys/values at max length

- **Attack**: Fill `metadata` VecMap with many entries, each with max-length strings.
- **Expected**: No limit on metadata entries in spec.
- **Spec defense**: None -- metadata is unbounded. DEFENDED at the Sui transaction size limit, but could bloat object storage.
- **Recommendation**: Add `MAX_METADATA_ENTRIES` (e.g., 20) and `MAX_METADATA_KEY_LENGTH` / `MAX_METADATA_VALUE_LENGTH` limits. Without these, a single bounty object could consume excessive storage.

---

## Category 6: Ordering Attacks

### 6.1 claim() and cancel() race on same bounty

- **Attack**: Hunter submits `claim()` tx, creator submits `cancel()` tx simultaneously. Both reference the same shared `Bounty<T>` object.
- **Expected**: Sui's object-based sequencing serializes them. One executes first.
- **Spec defense**: Sui shared object consensus orders transactions. If cancel goes first, claim sees non-Open status and aborts. If claim goes first, cancel handles active claims with penalty. DEFENDED.
- **Recommendation**: None -- Sui's architecture handles this correctly.

### 6.2 verify() and expire() race

- **Attack**: Verifier submits `verify()` at the same time someone submits `expire()` right after deadline.
- **Expected**: Serialized by Sui. If verify goes first, it succeeds (no deadline check on verify per spec). If expire goes first, bounty becomes Expired and verify fails on status check.
- **Spec defense**: SUSPICIOUS -- `verify()` has NO deadline check in the spec's per-function checks table. A verifier can verify after the deadline as long as no one has called `expire()` yet.
- **Recommendation**: This is arguably a feature (late verification should still count if the work was done). But it creates a race: if someone expires first, the hunter loses their stake even though work was completed. Consider adding a grace period: verify is allowed for X seconds after deadline even if expire has been called. OR add a deadline check to verify and force all verification to happen before deadline.

### 6.3 Multiple claims in same transaction (PTB)

- **Attack**: Use a Programmable Transaction Block to call `claim()` multiple times in the same transaction with different sender contexts.
- **Expected**: In a single PTB, the sender is fixed. `claimed_hunters` VecSet would catch the duplicate on the second call.
- **Spec defense**: `claimed_hunters` VecSet + single sender per PTB. DEFENDED.
- **Recommendation**: None.

---

## Category 7: Type Confusion

### 7.1 Wrong Coin<T> type

- **Attack**: Bounty is `Bounty<SUI>`. Attacker tries to call `claim<USDC>(bounty, usdc_coin, ...)`.
- **Expected**: Move type checker rejects -- `bounty: &mut Bounty<T>` and `stake_coin: Coin<T>` must share the same `T`. Passing `Bounty<SUI>` with `Coin<USDC>` is a type mismatch.
- **Spec defense**: Move generics enforce type consistency at compile/runtime. DEFENDED.
- **Recommendation**: None.

### 7.2 Pass ClaimTicket to wrong bounty's destroy_ticket

- **Attack**: Call `destroy_ticket(ticket_for_A, bounty_B)` where bounty_B is in terminal state but bounty_A is not.
- **Expected**: Should check `ticket.bounty_id == bounty.id`.
- **Spec defense**: Spec shows `destroy_ticket(ticket: ClaimTicket, bounty: &Bounty<T>, ...)`. The bounty_id matching check should be enforced. DEFENDED (assuming implementation checks this).
- **Recommendation**: Ensure `destroy_ticket` validates `ticket.bounty_id == bounty.id`. The spec doesn't explicitly list this check -- add it to the per-function checks table.

---

## Category 8: DoS Vectors

### 8.1 Fill VecSet/VecMap to max (100 entries)

- **Attack**: 100 different addresses each claim. `claimed_hunters` VecSet has 100 entries. `active_hunter_stakes` VecMap has 100 entries. On `cancel()`, iterating all 100 entries for penalty distribution.
- **Expected**: Gas cost scales linearly. At max_claims=100, this should be within Sui gas limits.
- **Spec defense**: `MAX_CLAIMS = 100` caps the size. SUSPICIOUS -- needs gas benchmarking.
- **Recommendation**: Benchmark `cancel()` with 100 active claims. VecMap iteration is O(n) per lookup too. If gas is borderline, reduce MAX_CLAIMS to 50, or restructure cancel to not iterate (e.g., use a withdrawal pattern where each hunter claims their own penalty). The current design requires a single `cancel()` tx to pay ALL hunters atomically -- this could hit gas limits.

### 8.2 Create thousands of bounties (board spam)

- **Attack**: Spam `create()` to flood the bounty board with garbage bounties.
- **Expected**: Each creation costs gas + locks escrow. But with minimum `reward_amount = 1` and `max_claims = 1`, cost is ~1 token + gas per bounty.
- **Spec defense**: No anti-spam mechanism. SUSPICIOUS.
- **Recommendation**: Protocol level: consider a non-refundable creation fee (even 0.01 SUI). Application level: implement off-chain indexing with filters, reputation scores, and pagination. The protocol itself should remain permissionless, but document the spam risk.

### 8.3 Claim and abandon loop to bloat claimed_hunters

- **Attack**: Hunter A claims, abandons (stake forfeited). Hunter A is permanently in `claimed_hunters` and cannot claim again. But the VecSet entry persists forever.
- **Expected**: Each unique address adds one entry. `claimed_hunters` never shrinks. After `max_claims` unique addresses have claimed (even if all abandoned), no one else can claim.
- **Spec defense**: `claimed_hunters` includes abandoned hunters. `max_claims` limits entries. DEFENDED -- bounded by MAX_CLAIMS.
- **Recommendation**: Wait -- this is actually a subtle issue. `claimed_hunters` prevents re-claiming, and it includes abandoned hunters. So if `max_claims = 5` and 5 different hunters each claim and abandon, the bounty has `active_claims = 0` but `claimed_hunters.size() = 5`. Can a 6th hunter claim? The check is `active_claims < max_claims`, so YES the 6th hunter can claim. But `claimed_hunters` will grow beyond `max_claims`. This is fine for the VecSet (bounded by total unique addresses that ever interacted), but it could grow larger than MAX_CLAIMS. **Clarify in spec**: `claimed_hunters` can exceed `max_claims` size. Ensure no code assumes `claimed_hunters.size() <= max_claims`.

---

## Combo Attacks

### C.1 Economic + Arithmetic: Cleanup reward self-dealing with rounding

- **Attack**: Create bounty with `escrow = 10001`, `cleanup_reward_bps = 999` (9.99%). `calculate_cleanup_reward(10001, 999) = 10001 * 999 / 10000 = 9990`. Creator gets back `10001 - 9990 = 11`. If attacker is both creator and expirer, they get `9990 + 11 = 10001` back minus gas. Net loss = gas only.
- **Status**: Not exploitable for profit. DEFENDED (self-dealing).

### C.2 Access Control + Object: Destroy someone else's ClaimTicket

- **Attack**: After a bounty expires, call `destroy_ticket()` passing someone else's ticket.
- **Expected**: `ClaimTicket` has `key` only (no `store`). Only the owner can pass it as a transaction argument in Sui. An attacker cannot reference someone else's owned object.
- **Status**: DEFENDED by Sui's owned object model.

### C.3 Ordering + Economic: Front-run expire with last-second verify

- **Attack**: Verifier watches mempool. Sees someone about to call `expire()`. Quickly submits `verify()` for a hunter who didn't actually complete work. Hunter gets reward + stake, creator loses funds.
- **Expected**: Sui doesn't have a public mempool in the traditional sense. Shared object transactions go through consensus. But if verifier is already colluding, they don't need to front-run -- they can verify anytime.
- **Status**: Reduces to collusion attack (4.5). DEFENDED by Sui's consensus model against external front-running.

### C.4 DoS + Economic: Grief cancel by filling all slots

- **Attack**: Sybil attacker fills all `max_claims` slots with minimum stake. Creator wants to cancel but must pay `required_stake * max_claims` in penalties from escrow. If `required_stake * max_claims > escrow` (possible after some verifies), creator is trapped.
- **Expected**: Creator cannot cancel, must wait for expire. On expire, sybil attacker loses all stakes.
- **Status**: Attacker loses `required_stake * max_claims` tokens. Only profitable if the goal is to grief the creator. SUSPICIOUS -- griefing attack with a cost.
- **Recommendation**: Document this risk. Creators should set `required_stake` high enough that squatting is expensive, but not so high that penalty exceeds remaining escrow.

---

## Critical Findings (Ordered by Severity)

### HIGH -- Must fix before implementation

1. **[2.5] Overflow in `calculate_cleanup_reward`**: `total * bps` can overflow u64 for large escrow values. Use u128 intermediate arithmetic.

2. **[8.1] Gas limit on `cancel()` with max active claims**: Cancel iterates all active hunters to distribute penalties. At 100 hunters, this may exceed gas limits. Benchmark required; consider reducing MAX_CLAIMS or switching to withdrawal pattern.

### MEDIUM -- Should fix

3. **[2.2] Zero cleanup reward for small bounties**: Rounding to zero removes economic incentive for expiration. Add minimum floor or document limitation.

4. **[6.2] Verify/expire race condition**: No deadline check on verify means late verification races with expiration. Define explicit policy.

5. **[5.1] Empty title allowed**: Enables low-effort spam bounties. Add minimum length check.

6. **[5.4] Unbounded metadata**: No limit on metadata entries. Add `MAX_METADATA_ENTRIES`.

7. **[8.3] `claimed_hunters` can exceed `max_claims`**: Spec should clarify this is intentional and implementation should not assume bounded size.

### LOW -- Document as known limitations

8. **[1.5] Sybil resistance**: Creator can claim own bounty via second address. Unsolvable on-chain.

9. **[4.4] Cleanup reward farming / spam**: Self-dealing has no profit but pollutes state.

10. **[4.5] Creator-verifier collusion**: Inherent trust assumption. Document explicitly.

11. **[4.1] Impossible conditions griefing**: Creator can set absurd parameters. Application-layer concern.

---

## Recommended Spec Amendments

```
1. calculate_cleanup_reward():
   - Use u128 intermediate: (total as u128) * (bps as u128) / 10000
   - Add minimum reward floor: max(calculated, 1) when bps > 0 and total > 0

2. create() additional checks:
   - title.length() > 0                     → E_TITLE_EMPTY
   - metadata.size() <= MAX_METADATA_ENTRIES → E_TOO_MANY_METADATA
   - Consider: deadline >= now + MIN_DURATION → E_DEADLINE_TOO_SOON

3. cancel() gas safety:
   - Benchmark with MAX_CLAIMS active hunters
   - If gas exceeds limit, implement withdrawal pattern:
     cancel() only marks state as Cancelled
     withdraw_penalty() lets each hunter pull their own funds

4. verify() deadline policy (choose one):
   - Option A: Add deadline check (verify must happen before deadline)
   - Option B: No deadline check (current design), document the race risk
   - Option C: Grace period (verify allowed up to X seconds after deadline)

5. destroy_ticket() per-function checks:
   - Add explicit check: ticket.bounty_id == bounty.id

6. Security Model section:
   - Document: "Protocol trusts the designated verifier. Collusion is outside threat model."
   - Document: "Sybil resistance is not provided. Applications should add reputation layers."
   - Document: "required_stake = 0 provides no hunter protection against cancellation."

7. claimed_hunters clarification:
   - Explicitly state: claimed_hunters may grow beyond max_claims due to abandon cycles
   - Ensure no invariant assumes claimed_hunters.size() <= max_claims
```

---

## Test Recommendations for Implementation Phase

When code exists, re-run red team with executable attack tests. Priority tests:

| Priority | Test | Validates |
|---|---|---|
| P0 | `cancel()` with 100 active claims -- measure gas | Finding 8.1 |
| P0 | `calculate_cleanup_reward(u64::MAX, 1000)` | Finding 2.5 |
| P0 | `expire()` with escrow=99, bps=1 -- verify cleanup_reward | Finding 2.2 |
| P1 | `create()` with title="" | Finding 5.1 |
| P1 | `verify()` after deadline but before expire | Finding 6.2 |
| P1 | `destroy_ticket()` with mismatched bounty_id | Finding 7.2 |
| P1 | 5 claim + 5 abandon + 5 new claim -- check claimed_hunters size | Finding 8.3 |
| P2 | Full lifecycle with `required_stake = 0` | Finding 2.3 |
| P2 | `create()` with 50 metadata entries | Finding 5.4 |


### 2026 03 21 Examples Integration Wrappers Design

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

