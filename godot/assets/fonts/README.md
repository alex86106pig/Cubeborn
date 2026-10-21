# 字型

| 檔案 | 說明 |
|---|---|
| `NotoSansTC-VF.ttf` | Noto Sans TC（可變字重），HUD 與所有介面文字。網頁匯出時瀏覽器沒有系統字型，必須打包進專案 |
| `hud_font.tres` | 以 Noto Sans TC 為底、字重 700 的 FontVariation，設為專案預設字型（`project.godot` 的 `gui/theme/custom_font`） |

- 授權：SIL Open Font License 1.1（全文見 `OFL.txt`），可隨遊戲散布，不可單獨販售字型。
- 版權：Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'. Noto is a trademark of Google Inc.
- 來源：alex_donghu 電腦的 `C:\Windows\Fonts\NotoSansTC-VF.ttf`（與 Google Fonts 發布的 Noto Sans TC 相同家族）。
- 這套字型沒有 ⚔ 🛡 ✦ ✺，技能欄的武器圖示改由 `ui/skill_bar.gd` 直接畫。
