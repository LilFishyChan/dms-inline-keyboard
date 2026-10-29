#!/usr/bin/env python3
"""校验仓库里用到的 Material Symbols 图标名在 DMS 自带字体里真实存在。

为什么需要：`DankIcon { name: "..." }` 的 name 是字体连字（ligature）。
写错一个字母不会报任何错，只是画不出字形 —— 键帽看起来是空的。
（踩过：Del 写成 "backspace_outline"，字体里只有 "backspace"，
 「特殊键显示方式 = 图标」时 Del 就是个空键帽。）

用法：
    python3 tools/check-icons.py            # 检查，退出码 1 表示有不存在图标名
    python3 tools/check-icons.py -v         # 顺带列出命中的全部名字

字体位置：DMS 运行时把资源解到 $XDG_RUNTIME_DIR/dms-shell/<hash>/DCommon/assets/fonts/
里，hash 每次重启可能变，所以用 glob 找最新的那个。
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

FONT_PATTERNS = [
    os.path.expandvars("$XDG_RUNTIME_DIR/dms-shell/*/DCommon/assets/fonts/"
                       "material-design-icons/**/*.ttf"),
    os.path.expanduser("~/.config/dms/**/material-design-icons/**/*.ttf"),
    "/usr/share/dankmaterialshell/**/material-design-icons/**/*.ttf",
]


def find_font():
    for pattern in FONT_PATTERNS:
        hits = glob.glob(pattern, recursive=True)
        if hits:
            # 变量字体只有一个；多个就按 mtime 取最新的（对应正在跑的 DMS）
            return max(hits, key=os.path.getmtime)
    return None


def font_ligatures(path):
    from fontTools.ttLib import TTFont

    font = TTFont(path)
    names = set()

    def walk(subtable):
        # LookupType 7 = Extension：真正的 SubTable 在里面
        if subtable.LookupType == 7:
            walk(subtable.ExtSubTable)
            return
        if hasattr(subtable, "ligatures"):
            for first, ligs in subtable.ligatures.items():
                for lig in ligs:
                    # 字形名把 "_" 拼成 "underscore"，转回来才是图标名
                    names.add((first + "".join(lig.Component))
                              .replace("underscore", "_").lower())

    for lookup in font["GSUB"].table.LookupList.Lookup:
        for subtable in lookup.SubTable:
            try:
                walk(subtable)
            except Exception:
                pass
    return names


# special-keys.js 里的 { icon: "名字" }
RE_JS_ICON = re.compile(r'icon:\s*"([A-Za-z0-9_]+)"')
# 组件里的 name: "名字"，只在 DankIcon / DIcon 块附近才算
RE_QML_NAME = re.compile(r'\bname:\s*"([A-Za-z0-9_]+)"')
RE_ICON_BLOCK = re.compile(r'\b(DankIcon|DIcon)\s*\{')


def check(repo, names, verbose=False):
    missing = []
    checked = 0

    def verify(where, icon):
        nonlocal checked
        checked += 1
        if verbose:
            print(f"  {icon:32s} {where}")
        if icon.lower() not in names:
            missing.append((where, icon))

    # 1) 特殊键表（图标形态直接用它）
    sk = os.path.join(repo, "layouts", "special-keys.js")
    if os.path.exists(sk):
        with open(sk, encoding="utf-8") as f:
            for m in RE_JS_ICON.finditer(f.read()):
                verify("layouts/special-keys.js", m.group(1))

    # 2) QML 里 DankIcon / DIcon 的字面量 name
    for path in sorted(glob.glob(os.path.join(repo, "*.qml"))):
        with open(path, encoding="utf-8") as f:
            src = f.read()
        for block in RE_ICON_BLOCK.finditer(src):
            # 只看这个块后面一小段，避免误伤 Image/Repeater 之类的 name
            tail = src[block.end(): block.end() + 600]
            for m in RE_QML_NAME.finditer(tail):
                verify(os.path.basename(path), m.group(1))
    return checked, missing


def main():
    verbose = "-v" in sys.argv
    font = find_font()
    if not font:
        print("找不到 DMS 的 Material Symbols 字体（DMS 没在跑？）")
        print("路径样例：$XDG_RUNTIME_DIR/dms-shell/*/DCommon/assets/fonts/"
              "material-design-icons/variablefont/*.ttf")
        return 2

    print(f"字体: {font}")
    names = font_ligatures(font)
    print(f"连字数: {len(names)}\n")

    checked, missing = check(REPO, names, verbose)
    if not missing:
        print(f"✓ {checked} 个图标名全部存在于字体里")
        return 0

    print(f"✗ {checked} 个里 {len(missing)} 个字体里没有（会渲染成空白）：")
    for where, icon in missing:
        print(f"  {where}: {icon}")
    print("\n挑一个真实存在的名字再改。查法：")
    print("  python3 -c \"import tools.check_icons as c; n=c.font_ligatures(c.find_font());"
          " print([x for x in n if 'todo' in x])\"")
    return 1


if __name__ == "__main__":
    sys.exit(main())
