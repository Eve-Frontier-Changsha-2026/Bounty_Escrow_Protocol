# Bounty Escrow Protocol — 開發計畫

> 層級：基礎設施層（全生態共用）
> 定位：無信任鏈上懸賞，自動驗證 + 撥款

---

## 架構定位

```
應用層 (Explorer / Fleet / DAO) ──呼叫──▶ Bounty Escrow Protocol
```

被上層三個應用共同依賴，是整個生態的任務 + 金流引擎。

---

## 開發階段

### Phase 0：前置準備
- [ ] 建立 Sui Move 專案結構（`move/` 目錄、Move.toml）
- [ ] 確認 Sui SDK 版本、開發網路 (devnet/testnet)

### Phase 1：核心合約
- [ ] 設計合約架構（Bounty Object、Escrow Fund、Verification Logic）
- [ ] 實作核心 Move Module
  - `bounty::create` — 發布懸賞 + 鎖定資金
  - `bounty::claim` — 接取任務
  - `bounty::verify` — 鏈上事件驗證（Killmail、Storage Transfer 等）
  - `bounty::payout` — 驗證通過後自動撥款
  - `bounty::cancel` — 發布者取消 + 退款
- [ ] Escrow 資金鎖定與釋放機制
- [ ] 鏈上事件驗證接口設計

### Phase 2：測試
- [ ] 單元測試（各 entry function）
- [ ] 極端測試（重複 claim、超時、惡意驗證）
- [ ] 部署到 devnet

### Phase 3：上層整合接口
- [ ] 提供給 Explorer Hub 的情報懸賞接口
- [ ] 提供給 Fleet Command 的戰鬥合約接口
- [ ] 提供給 DAO 的後勤任務接口

---

## 技術待確認
- [ ] 鏈上事件驗證的具體實現方式（Oracle? 直接讀鏈上事件?）
- [ ] Bounty Object 是 Shared Object 還是 Owned Object?
- [ ] 超時 / 過期懸賞的處理機制

---

## TODO
- [ ] 合約架構設計文檔
- [ ] 核心 Move Module 實作
- [x] 建立獨立專案 + 各專案 README 交叉引用
