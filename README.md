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
