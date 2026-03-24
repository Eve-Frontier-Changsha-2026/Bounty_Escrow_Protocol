# Notes — Bounty Escrow Protocol

## 2026-03-24: v5 Task Type System 架構決策

### 核心決策

1. **任務類型 5 種**: CUSTOM(0), KILL(1), DELIVERY(2), BUILD(3), INTEL(4)
2. **驗證路徑 3 條**:
   - **Auto (Path A)**: 傳入鏈上 shared object 直接驗證 — KILL(&Killmail), BUILD(&Assembly)
   - **Oracle (Path B)**: backend 查 indexer event → Ed25519 簽名 attestation → 合約驗簽 — DELIVERY
   - **Seal (Path C)**: 加密情報 + creator confirm — INTEL
   - **Manual (Path D)**: 現有 proof + arbitrator 流程 — CUSTOM (backward compat)

### EVE Frontier World Contract 可用資料

| 資料 | 鏈上形態 | 可驗證? |
|-----|---------|--------|
| 擊殺 | `Killmail` shared object: killer_id, victim_id, kill_timestamp, solar_system_id | 直接 |
| 物資存取 | `ItemDepositedEvent`: assembly_id, character_id, type_id, quantity | 需 oracle |
| 建築 | `Assembly` shared object: owner_cap_id, status, location (但無 public type_id accessor) | 部分直接 + oracle |
| 情報 | 無鏈上表示 | 不可 → Seal 加密 |

### World Contract 限制

- **Assembly 無 `type_id()` public accessor** — BUILD 驗證只能用 &Assembly 驗 ownership，type_id 需 oracle attestation
- **Inventory 是 `store` not `key`** — 不能跨合約直接讀，DELIVERY 只能用 oracle
- **Location 是 hashed** — 無法直接比對 solar_system，需 oracle 或 location reveal

### Oracle 設計（獨立可重用）

- `OracleRegistry` shared object，admin 管理 oracle 地址
- Ed25519 自帶驗簽（`sui::ed25519` + `sui::hash`），不依賴 `world::sig_verify`
- Attestation BCS format: `{ bounty_id, hunter, item_type_id, quantity, assembly_id, timestamp, nonce }`
- Nonce replay 防護: `OracleNonceKey { nonce }` DF per bounty

### Seal 情報交易（仿 Frontier Explorer Hub）

- Hunter 用 Seal SDK 加密 intel → `post_intel()` 存 encrypted_payload (max 4096 bytes)
- Mint `ViewerReceipt` 給 creator → Seal key server 呼叫 `seal_approve()` → creator 解密
- Creator 確認 OK → `confirm_intel()` → auto-approve
- Creator 不滿意 → 進入現有 dispute 流程
- 一個願打一個願挨模式

### 合約擴展 pattern

- **所有新功能用 Dynamic Field** — 零 Bounty struct layout 變更
- `bounty.move` 加 3 個 `public(package)` fn: `auto_verify_approve`, `uid`, `uid_mut`
- 新 module 透過 `uid_mut` 讀寫 bounty 上的 DF
- 向後相容: 無 TaskTypeKey DF → 預設 CUSTOM

### Red Team 5 攻擊向量

1. Killmail replay → UsedKillmailKey DF
2. Oracle attestation replay → OracleNonceKey DF
3. Intel frontrun → creator 必須 confirm，無 auto-approve timer
4. Task type mutation → set_task_type 需 OPEN + 0 active_claims + DF 不存在
5. Character spoofing → `character.character_address() == ctx.sender()` check

### 檔案結構

```
bounty_escrow/sources/
├── bounty.move          (MODIFY — +3 public(package) fns, ~40 lines)
├── constants.move       (MODIFY — +task types, +errors 61-83, ~40 lines)
├── task_type.move       (NEW ~200 lines)
├── oracle.move          (NEW ~180 lines)
├── intel_escrow.move    (NEW ~150 lines)
├── verify_kill.move     (NEW ~120 lines)
├── verify_build.move    (NEW ~100 lines)
├── verify_delivery.move (NEW ~120 lines)
├── escrow.move          (NO CHANGE)
├── verifier.move        (NO CHANGE)
├── display.move         (NO CHANGE)
```

Move.toml 加 world dependency (for Killmail, Assembly, Character types)
