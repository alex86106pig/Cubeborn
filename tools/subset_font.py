# 網頁版字型子集化（CI 用，v0.34.2）：NotoSansTC-VF.ttf 只留遊戲程式裡出現過的字，原地覆蓋（repo 裡照常放完整字型）
# 用法（專案根目錄）：python3 -m venv venv && venv/bin/pip install fonttools && venv/bin/python tools/subset_font.py
# 收集範圍：godot/ 底下的 .gd / .tscn / .tres / .cfg（含註解，寧可多留）+ ASCII + 常用全形標點；保留粗細軸（HUD 用字重 700）
# CI 接著跑 check.gd 的「字型」檢查，介面文字缺字會直接失敗
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent / "godot"
FONT = ROOT / "assets" / "fonts" / "NotoSansTC-VF.ttf"
SOURCE_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg"}


def collect_text() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}            # ASCII（IP 輸入、數字）
    chars |= {chr(c) for c in range(0x3000, 0x3040)}       # CJK 標點
    chars |= {chr(c) for c in range(0xFF01, 0xFF5F)}       # 全形符號
    for p in ROOT.rglob("*"):
        if p.suffix in SOURCE_SUFFIXES and ".godot" not in p.parts:
            chars |= set(p.read_text(encoding="utf-8"))
    return "".join(sorted(c for c in chars if c >= " "))


def main() -> int:
    text = collect_text()
    before = FONT.stat().st_size
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    font = TTFont(FONT)
    sub = subset.Subsetter(options=opts)
    sub.populate(text=text)
    sub.subset(font)
    font.save(FONT)
    after = FONT.stat().st_size
    print(f"subset {FONT.name}: {len(text)} chars, {before / 1e6:.2f} MB -> {after / 1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
