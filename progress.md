# Bounty Escrow Protocol — 進度追蹤

> 格式：最新紀錄放最上面

---

## 狀態

| 階段 | 狀態 |
|------|:----:|
| 設計文檔 | ✅ |
| 合約實作 | ⬜ |
| 測試 | ⬜ |
| 部署 | ⬜ |
| 上層整合 | ⬜ |

---

## 進度日誌

### 2026-03-20 — Spec 設計 + 三方審查

#### 做了什麼
- 完成完整 System Design Spec（brainstorming → design → review）
- 經過 sui-architect、sui-security-guard、sui-red-team 三方平行審查
- 修正 13 項關鍵問題，包括：
  - verify 流程改為 two-step（approve → claim_reward），解決 Sui owned-object 限制
  - cancel 改為 withdrawal pattern，解決 100 人 gas 爆炸 + 映射現實「申報債權」
  - 加入 grace period（驗收補救期）防止 verify/expire 競態
  - 加入 MIN/MAX_DEADLINE_DURATION 防超短/超長 deadline 攻擊
  - 加入 version 欄位 + 升級策略文件
  - 加入 Publisher + Display V2
  - 所有 entry function 加 public fun 版本供上層合約組合
  - u128 中間運算防溢出
  - metadata/title 邊界檢查
- 確立「Game-as-Reality」設計哲學 — 每個機制映射現實商業行為
- Red team report 獨立保存

#### 更動/新增了哪些檔案
- `[NEW] docs/superpowers/specs/2026-03-20-bounty-escrow-protocol-design.md`
- `[NEW] docs/superpowers/specs/2026-03-20-red-team-report.md`

#### 關鍵設計決策
- Two-step verify = 現實「驗收→請款」
- Withdrawal pattern = 現實「公告取消→各自領違約金」
- Grace period = 合約法「補救期」
- Cleanup reward = 拾荒者經濟
- Hunter stake = 履約保證金

---

### 2026-03-20 — 獨立專案建立

#### 做了什麼
- 建立獨立專案 `Bounty_Escrow_Protocol`，定位為全生態共用的底層任務與資金託管合約
- 在 Explorer Hub、Fleet Command、DAO 三個 README 加入交叉引用
- 確立 Infrastructure + Composability 架構方向

#### 更動/新增了哪些檔案
- `[NEW] README.md`
- `[MODIFY] ../Frontier_Explorer_Hub/README.md`
- `[MODIFY] ../Fleet_Command_Doctrine/README.md`
- `[MODIFY] ../Tribal_Governance_DAO/README.md`

#### 決策原因
- Bounty 提升為底層 Protocol 最大化程式碼複用，展示 Sui Composability，讓三套獨立專案有經濟動能交集。
