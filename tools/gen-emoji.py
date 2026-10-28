#!/usr/bin/env python3
"""生成 layouts/emoji.js：表情分组（Unicode 官方 emoji-test.txt）+ 符号分组。

为什么是生成文件而不是运行时去读系统数据：
键盘要在没有网络的平板上也能用，而且 fcitx5 的 emoji 词库是二进制格式；
唯一稳定、可复现的来源就是 Unicode 官方清单，生成一次随仓库提交。

用法：
    python3 tools/gen-emoji.py                 # 没缓存就下载 16.0
    python3 tools/gen-emoji.py --input X.txt   # 用本地文件
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import unicodedata
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "layouts", "emoji.js")
CACHE = os.path.join(HERE, ".cache", "emoji-test-16.0.txt")
URL = "https://www.unicode.org/Public/emoji/16.0/emoji-test.txt"

# 官方分组 → 内部 id。顺序跟着 emoji-test.txt 走，跟系统键盘一致。
EMOJI_GROUP_IDS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Travel & Places": "travel",
    "Activities": "activities",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}
# Component 组是肤色色块，不是表情，跳过
SKIP_GROUPS = {"Component"}

SKIN_TONES = set(range(0x1F3FB, 0x1F400))

# 符号：按用途分段，取 Unicode 区段里「已分配且不是表情」的字符
SYMBOL_GROUPS = [
    ("math", "Math", [(0x2200, 0x22FF), (0x2A00, 0x2AFF),
                      (0x00B1, 0x00B1), (0x00D7, 0x00D7), (0x00F7, 0x00F7)]),
    ("punct", "Punctuation", [(0x2010, 0x206F), (0x3000, 0x303F),
                              (0xFF01, 0xFF0F), (0xFF1A, 0xFF20),
                              (0xFF3B, 0xFF40), (0xFF5B, 0xFF65)]),
    ("arrows", "Arrows", [(0x2190, 0x21FF), (0x27F0, 0x27FF),
                          (0x2900, 0x297F), (0x2B00, 0x2BFF)]),
    ("currency", "Currency", [(0x00A2, 0x00A5), (0x20A0, 0x20CF)]),
    ("shapes", "Shapes", [(0x25A0, 0x25FF)]),
    ("box", "Box drawing", [(0x2500, 0x257F)]),
    ("numbers", "Numbers", [(0x2150, 0x218F), (0x2460, 0x24FF)]),
    ("misc", "Misc", [(0x2100, 0x214F), (0x2600, 0x26FF)]),
]


def fetch(path: str) -> str:
    if os.path.exists(path):
        return path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    print("downloading", URL, file=sys.stderr)
    urllib.request.urlretrieve(URL, path)
    return path


def parse_emoji(path: str) -> list[dict]:
    groups: list[dict] = []
    current = None
    seen: set[str] = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("# group:"):
                name = line.split(":", 1)[1].strip()
                if name in SKIP_GROUPS or name not in EMOJI_GROUP_IDS:
                    current = None
                else:
                    current = {"id": EMOJI_GROUP_IDS[name], "label": name, "items": []}
                    groups.append(current)
                continue
            if line.startswith("#") or not line:
                continue
            if "; fully-qualified" not in line:
                continue
            if current is None:
                continue
            points = line.split(";", 1)[0].split()
            codes = [int(p, 16) for p in points]
            # 带肤色的变体不计入：全量 1900 个是不含肤色修饰的基础集
            if any(c in SKIN_TONES for c in codes):
                continue
            char = "".join(chr(c) for c in codes)
            if char in seen:
                continue
            seen.add(char)
            current["items"].append(char)
    return [g for g in groups if g["items"]]


def is_symbol(ch: str) -> bool:
    cat = unicodedata.category(ch)
    if cat in ("Cn", "Cs", "Co", "Zl", "Zp", "Zs", "Cc", "Cf"):
        return False
    # 组合用符号、变体选择符不要（单独出现没有意义）
    if cat.startswith("M"):
        return False
    return True


def parse_symbols(emoji_chars: set[str]) -> list[dict]:
    groups = []
    for gid, label, ranges in SYMBOL_GROUPS:
        items = []
        for lo, hi in ranges:
            for code in range(lo, hi + 1):
                ch = chr(code)
                if not is_symbol(ch):
                    continue
                # 表情页里已经有的字符不重复出现在符号页
                if ch in emoji_chars:
                    continue
                items.append(ch)
        groups.append({"id": gid, "label": label, "items": items})
    return [g for g in groups if g["items"]]


def js_groups(groups: list[dict], indent: str = "    ") -> str:
    out = []
    for g in groups:
        # 一项一个字符串：表情里有 ZWJ 组合序列（👨‍👩‍👧），
        # 拼成一个大字符串再切会把组合序列切碎，只能逐项输出
        lines = []
        items = g["items"]
        for i in range(0, len(items), 24):
            chunk = ", ".join(json.dumps(c, ensure_ascii=False)
                              for c in items[i:i + 24])
            lines.append(f"{indent}    {chunk}")
        body = ",\n".join(lines)
        out.append(f'{indent}{{id: "{g["id"]}", label: {json.dumps(g["label"])}, '
                   f'items: [\n{body}\n{indent}]}}')
    return ",\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()

    path = fetch(args.input or CACHE)
    emoji = parse_emoji(path)
    emoji_chars = {c for g in emoji for c in g["items"]}
    symbols = parse_symbols(emoji_chars)

    total_emoji = sum(len(g["items"]) for g in emoji)
    total_symbols = sum(len(g["items"]) for g in symbols)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("// 生成文件，勿手改：python3 tools/gen-emoji.py\n")
        fh.write(f"// 来源：Unicode 16.0 emoji-test.txt（{total_emoji} 个表情，"
                 f"不含肤色变体）/ 符号 {total_symbols} 个\n")
        fh.write(".pragma library\n\n")
        fh.write("var emojiGroups = [\n")
        fh.write(js_groups(emoji))
        fh.write("\n]\n\n")
        fh.write("var symbolGroups = [\n")
        fh.write(js_groups(symbols))
        fh.write("\n]\n\n")
        fh.write("""// 「全部」= 各分组顺次拼起来（UI 里的默认分类）
function flatten(groups) {
    var out = []
    for (var i = 0; i < groups.length; i++) {
        var items = groups[i].items
        for (var j = 0; j < items.length; j++)
            out.push(items[j])
    }
    return out
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        emojiGroups: emojiGroups,
        symbolGroups: symbolGroups,
        flatten: flatten
    }
}
""")
    print(f"ok: {total_emoji} emoji / {total_symbols} symbols → {args.out}")


if __name__ == "__main__":
    main()
