# Move Notes — Bounty Escrow Protocol

## 2026-03-24: v4 Dispute Fairness — Arbitrator + Auto-Resolve + Withdraw

**目的：** 修復 `resolve_dispute` 球員兼裁判問題。Creator 不再自己裁決 dispute，改由獨立仲裁者或 timeout 自動 approve。Hunter 可主動退出拿回 stake。

**改動：**

### 新增 structs（Dynamic Fields）
- `ArbitratorConfigKey {}` → `ArbitratorConfig { arbitrator, dispute_timeout_ms }` — 每個 bounty 可選設定
- `DisputeTimestampKey { hunter }` → `DisputeTimestamp { disputed_at }` — 記錄 dispute 發起時間，供 auto-resolve 驗證 timeout

### 新增 functions
| Function | 說明 |
|----------|------|
| `set_arbitrator<T>` | Creator 設定仲裁者 + timeout（OPEN + 0 claims 才能設，不可設自己） |
| `auto_resolve_dispute<T>` | Permissionless，任何人可呼叫，dispute timeout 到期自動 approve hunter |
| `withdraw_from_bounty<T>` | Hunter 主動退出，stake 退回 hunter（vs `abandon` 沒收給 creator） |
| `has_arbitrator<T>` / `arbitrator_address<T>` / `dispute_timeout<T>` | Accessors |

### 修改 functions
- `dispute_rejection<T>` — 加寫 `DisputeTimestampKey` DF
- `resolve_dispute<T>` — auth 改為 arbitrator (有設定時) / creator (fallback)，清理 DisputeTimestamp DF

### 新增 constants
- Error codes: 52-60（`e_not_arbitrator`, `e_creator_is_arbitrator`, `e_dispute_timeout_too_short/long`, `e_dispute_not_timed_out`, `e_hunter_has_active_proof`, `e_hunter_is_approved`, `e_no_dispute_timestamp`）
- Timeout: default 7 days, min 1 day, max 30 days

### 新增 events
- `ArbitratorSetEvent`, `DisputeAutoResolvedEvent`, `HunterWithdrawnEvent`

**設計決策：**
- DF 擴展模式（與 v3 ProofKey/ReviewConfigKey 一致），無 struct layout 變更
- 向後相容：舊 bounty 無 ArbitratorConfig → creator resolve（現有行為不變）
- `withdraw` 只在 proof 為 `rejected`/`resolved_rejected`/無 proof 時允許（防 submit 垃圾 → dispute → 撈 stake）
- `withdraw` 有 deadline+grace_period guard（expire 後 stake_pool 已清空）
- Arbitrator 可與 verifier 相同（不同角色）

**測試：** 131 tests all passed（含 1 個 test 更新 expected error code 13→52）。

**已知風險：**
- `dispute_timeout_ms` 可能 > `grace_period`，導致 auto-resolve 在 expire 前來不及觸發。UI 應警告。
- 無仲裁者防串通機制（仲裁者公開透明，hunter claim 前自行判斷）

**後續：** 寫 v4 tests (~27 scenarios) → frontend 整合（`useArbitratorConfig`, `useDisputeTimestamp` hooks + UI）

---

## 2026-03-23: Testnet v3 Upgrade — Dispute Resolution

**Tx Digest:** `FexXFYE6Np4zF2wjWrzGWmRNpjs21syDbBFW3uDuQ9iR`

**目的：** 部署 Dispute Resolution v3（proof submission + dispute + auto-approve）到 testnet。

**部署資訊：**
| 欄位 | 值 |
|------|-----|
| Network | testnet (epoch 1046) |
| Original Package | `0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16` |
| v2 Package | `0x573d1c2f5a1ebd61aa178452887c6c2c4c9605556a6e9bbca54c543091651bcb` |
| v3 Package | `0x76b952d0acf15742daadb76f6b1921442bafbd8201d5449d2e0a73056a7df39c` |
| UpgradeCap | `0x10e4164c6dae28a5a861865852c794c462f1085bf277219a4e7eac47bcc8b7e9` |
| Modules | bounty, constants, display, escrow, verifier |
| Gas Used | ~0.139 SUI |

**v3 新增功能：**
- 7 new entry functions: set_review_period, submit_proof, reject_proof, resubmit_proof, dispute_rejection, resolve_dispute, auto_approve_proof
- Dynamic field 擴展（ProofKey + ReviewConfigKey），ABI-compatible
- 16 new error codes (36-51), 6 proof status codes (10-15)
- Red team v2 suspicious fixes（deadline check on dispute, abandon DF cleanup）

**測試：** 131 tests all passed。

**已知風險：** 無。upgrade policy 維持 compatible。

---

## 2026-03-21: Testnet v2 Upgrade — ABI-compatible refactor

**Commit:** `a3a1639`
**Tx Digest:** `DXG8vQMjqSfGqQHFZZ1rv5xS7w9fBpDcpyXKnjNUCHVK`

**目的：** 將所有 red team 修復 + composability 功能升級到 testnet。v1 的 `create_bounty<T>` 回傳 `(Coin<T>, ID)` 破壞 ABI 相容性，需重構。

**改動：** `bounty.move` — 三層結構：
- `create_bounty<T>` — 恢復 v1 signature，回傳 `Coin<T>`（ABI-compatible）
- `create_bounty_with_id<T>` — 新增，回傳 `(Coin<T>, ID)` for PTB composability
- `create_bounty_internal<T>` — private fun，共用核心邏輯

**部署資訊：**
| 欄位 | 值 |
|------|-----|
| Network | testnet (chain-id: 4c78adac) |
| Original Package | `0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16` |
| v2 Package | `0x573d1c2f5a1ebd61aa178452887c6c2c4c9605556a6e9bbca54c543091651bcb` |
| UpgradeCap | `0x10e4164c6dae28a5a861865852c794c462f1085bf277219a4e7eac47bcc8b7e9` |
| Gas Used | ~0.097 SUI |

**包含的安全修復（from red team）：**
- min_grace_period 驗證（1hr）
- approved hunter cancel penalty = reward_amount
- cancel_bounty escrow 區分 approved/unapproved penalty

**測試：** 97 tests all passed。

**已知風險：** 無。upgrade policy 維持 compatible。

---

## 2026-03-21: create_bounty<T> composability fix (superseded by v2 upgrade)

**Commit:** `5de24f9`

**目的：** 上層合約（如 Explorer Hub）呼叫 `create_bounty<T>` 後拿不到 bounty ID，無法在同一筆 PTB 裡原子性建立關聯 metadata object。

**改動：** `bounty.move` — `create_bounty<T>` 回傳型別從 `Coin<T>` 改為 `(Coin<T>, ID)`
- L174: 回傳型別
- L241: return `(change, bounty_id)`
- L258: `create` wrapper 解構 `let (change, _bounty_id) = ...`

**影響範圍：** 僅 `bounty.move`，3 行。`create` entry wrapper 內部適配，對終端使用者零影響。

**測試：** 55 tests all passed。

**已知風險：** 無。ID 在 `share_object` 前就已擷取（L220），share 後 ID 仍有效。

**後續：** Explorer Hub 可用新 API 在同一筆 PTB 建立 bounty + ExplorationMeta。

---

## 2026-03-21: Red Team Testing (10 rounds, 39 attack tests)

**目的：** 對核心合約進行對抗性安全測試，覆蓋 8 大攻擊類別 + 2 組合攻擊。

**結果：** 0 exploits / 3 suspicious / 36 defended (confidence 70%)

**測試檔案：** `tests/red-team/` 目錄，共 10 個測試檔。全部 94 tests passed (含既有 55 + 新增 39)。

### Suspicious 設計問題

1. **Cancel with `required_stake=0`** (`bounty.move:504-524`)
   - Creator 可建立零 stake bounty，讓 hunter 做工後 cancel，hunter 得不到任何補償。
   - 建議：前端警示 `required_stake=0` 的 bounty。

2. **Cancel after approval** (`bounty.move:495-524`)
   - Creator 在 verifier approve 後 cancel。Hunter 只拿回 `stake + required_stake`（penalty），而非 `stake + reward`。
   - Creator 淨省 `reward - required_stake`，低 stake 時是有利可圖的 griefing。
   - 建議：考慮 cancel 時若有 approved hunter，改為支付 full reward 或增加 penalty 倍數。

3. **`grace_period=0` 陷阱** (`bounty.move:362-386`)
   - grace=0 → verifier 在 deadline 後無法 approve，hunter 的 stake 在 expire 時被沒收。
   - 建議：加入 `min_grace_period` 驗證（如 1 小時）。

### 防禦確認

- **Access Control:** ClaimTicket soulbound（無 `store` ability）、VerifierCap bounty_id 綁定、creator-only 操作全部擋住。
- **Integer:** `checked_mul` u128 防溢位、`calculate_cleanup_reward` u128 中間值。
- **Object:** cross-bounty ticket 三種操作（claim_reward, abandon, withdraw_penalty）全部被 bounty_id mismatch 擋住。
- **Input Fuzzing:** title/description/max_claims/cleanup_bps 邊界全部正確。
- **Ordering:** 所有時間邊界（deadline exact, grace exact）行為符合預期。
- **DoS:** VecMap expire 清理、VecSet bloat 不影響功能。100 hunters 會在 test VM timeout，實際受 gas limit 約束。
- **State:** 雙重 cancel/expire、cancel expired bounty、self-claim 全部擋住。

### 已知限制

- `claimed_hunters` VecSet 只增不減（abandon 不移除），長期運行的 bounty 可能累積大量條目。目前 max_claims=100 足以約束。
- `grace_period` 無上限驗證，理論上可設極大值導致 `deadline + grace_period` overflow，但實際數值需 ~584M 年才觸發，非實際風險。

**後續：** 進入前端整合。

---

## 2026-03-21: Suspicious 設計問題修復

**目的：** 修復 red team 發現的 3 個 suspicious 設計問題。

**改動：**

1. **`constants.move`** — 新增 `min_grace_period(): u64 { 3_600_000 }` (1hr) + `e_grace_period_too_short(): u64 { 35 }`
2. **`bounty.move:188`** — `create_bounty` 加 `assert!(grace_period >= constants::min_grace_period())`
3. **`bounty.move:549-557`** — `withdraw_penalty_bounty` 判斷 hunter 是否在 `approved_hunters`：是則 penalty = `reward_amount`，否則 penalty = `required_stake`
4. **`bounty.move:514-519`** — `cancel_bounty` escrow 檢查改為區分 approved/unapproved 分別計算 penalty 總額

**影響範圍：** `constants.move`（2 行）、`bounty.move`（~15 行）。

**測試：** 97 tests all passed（+3 new: grace_period boundary tests + approved-penalty withdrawal test）。2 個 red team test 更新為 `expected_failure`。

**已知風險：** 無。cancel+zero-stake 非 approved hunter 不額外處理（前端警示即可）。

---

## 2026-03-23: Red Team v2 — Dispute Functions (10 rounds, 46 attack tests)

**目的：** 對 Dispute Resolution v3 的 7 個新 entry function 進行對抗性安全測試。

**結果：** 0 exploits / 2 suspicious / 44 defended (confidence 70%)

**測試檔案：** `tests/red-team/red_team_round_{11-20}_*.move`，測試後刪除（原 131 tests 不受影響）。全套 177 tests passed。

### 攻擊覆蓋

| Round | Category | Tests | Result |
|-------|----------|-------|--------|
| 11 | Access Control（dispute functions） | 6 | DEFENDED |
| 12 | Timing（review window manipulation） | 7 | 5 DEFENDED + 2 SUSPICIOUS |
| 13 | State Machine（invalid proof transitions） | 6 | DEFENDED |
| 14 | Economic（double approve via legacy+proof） | 4 | DEFENDED |
| 15 | Input Fuzzing（proof/reason fields） | 5 | DEFENDED |
| 16 | Ordering（cancel/expire during proof flow） | 4 | 3 DEFENDED + 1 SUSPICIOUS |
| 17 | DoS（grief via proof system） | 3 | DEFENDED |
| 18 | Combo（legacy approve + dispute） | 3 | DEFENDED |
| 19 | Combo（multi-hunter isolation） | 2 | DEFENDED |
| 20 | Combo（full lifecycle edge cases） | 6 | DEFENDED |

### Suspicious 設計問題（已修復 2026-03-23）

1. **`dispute_rejection` 無 deadline 檢查** — ✅ 已修復
   - 加 `assert!(now < bounty.deadline + bounty.grace_period, e_deadline_passed())`
   - 過期後不能發起新 dispute

2. **`abandon` 後 ProofSubmission dynamic field 孤立** — ✅ 已修復
   - `abandon_bounty` 中加 `dynamic_field::remove<ProofKey, ProofSubmission>` 清理
   - 測試 `test_abandon_with_pending_proof` 更新為驗證 DF 已清理

### 防禦確認（重點）

- **Access Control:** resolve_dispute 只有 creator 能呼叫（非 verifier、非 hunter、非第三方）。submit_proof / dispute_rejection / auto_approve_proof / resubmit_proof 只有 hunter 本人。reject_proof 需要 VerifierCap。
- **State Machine:** proof status 轉換嚴格：submitted→rejected→(resubmit→submitted | dispute→disputed→resolved)。無法跳狀態。
- **Economic:** legacy `approve_hunter` + proof system 的 `auto_approve_proof` 不會 double-approve（`e_already_auto_approved` / `e_already_approved` 交叉防護）。`resolve_dispute(approve)` 正確加入 `approved_hunters`。
- **Timing:** `reject_proof` 有 review window 限制，`auto_approve_proof` 要求 review period expired。`resubmit_proof` 正確重置 `submitted_at`。
- **Input:** 所有 string field（proof_url, proof_description, reason）有 empty + max_length 驗證。
- **Multi-hunter:** ProofKey 以 hunter address 為 key，不同 hunter 的 proof 完全隔離。
