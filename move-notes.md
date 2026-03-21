# Move Notes — Bounty Escrow Protocol

## 2026-03-21: create_bounty<T> composability fix

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
