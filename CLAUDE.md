# Cubeborn — AI 開發入口

這是一款 Three.js 等距視角 Roguelike 動作遊戲原型（暫定名 Cubeborn）。

## 每次開工必做
1. 先讀 [`PROJECT_GUIDELINES.md`](PROJECT_GUIDELINES.md)：技術棧、架構、命名慣例、工作流程都在裡面，所有修改必須遵守。
2. 讀 [`CHANGELOG.md`](CHANGELOG.md) 最上面一個版本，了解目前進度。
3. 只讀這次任務相關的模組，不要整包掃描 `src/`。

## 每次修改程式碼後必做
1. 在瀏覽器實際跑過並確認功能正常、Console 無錯誤。
2. 依版號規則更新 `CHANGELOG.md` 與 `src/core/version.js`。
3. git commit（訊息格式 `vX.Y.Z: 摘要`）並打 tag `vX.Y.Z`。
4. 回覆使用者時註明新版號與變更摘要。

## 架構有變動時
新增或刪除模組、改變核心規則（狀態機、CD、事件、資料格式）時，同步更新 `PROJECT_GUIDELINES.md`，讓它永遠是最新的事實來源。
