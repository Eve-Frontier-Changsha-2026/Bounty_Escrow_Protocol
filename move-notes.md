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
