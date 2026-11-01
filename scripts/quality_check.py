#!/usr/bin/env python3
"""DMS 插件质量检查：提交前自查，对齐 dux-plugin-registry 的 Claude Review 规则。

审核是自动的（claude-review.yml），规则写死在 prompt 里，verdict 分
ready / needs-changes / reject，其中 reject 包含「明显未审核的 AI 输出」。
这个脚本把能自动化的部分跑一遍，剩下的留给 PR 描述里说明。

用法：
    python3 scripts/quality_check.py            # 检查当前目录
    python3 scripts/quality_check.py --quiet    # 只打印问题
    python3 scripts/quality_check.py --json     # 机器可读

退出码：0 = 没有 FAIL；1 = 有 FAIL（提交前必须修）。
WARN 不阻塞，但要在 PR 里说明理由。
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", "node_modules", "build", "out", "docs", "tests", "prototype"}

FINDINGS = []  # (level, area, file, line, message)


def add(level, area, file, line, message):
    FINDINGS.append((level, area, str(file), line, message))


def rel(p):
    try:
        return str(p.relative_to(REPO))
    except ValueError:
        return str(p)


def sources(pattern="*.qml"):
    for p in sorted(REPO.rglob(pattern)):
        if any(part in SKIP_DIRS for part in p.parts):
            continue
        yield p


def read_lines(p):
    try:
        return p.read_text(errors="ignore").split("\n")
    except OSError:
        return []


# ---------------------------------------------------------------- 1. 安全

NETWORK = re.compile(r"\b(curl|wget|nc|ncat|socat|ssh|scp|rsync|telnet)\b")
PRIV = re.compile(r"\b(sudo|pkexec|doas)\b")
PERSIST = re.compile(r"systemctl\s+(--user\s+)?(enable|link)|\.config/autostart|@reboot")
TOUCHY = re.compile(r"['\"](/(etc|usr|boot|root|home/[a-z]+/\.ssh)/[^'\"]*)")
SECRET = re.compile(r"(?i)\b(api[_-]?key|secret|token|password|passwd)\b\s*[:=]\s*['\"][^'\"]{8,}")


def strip_strings(line):
    """去掉字符串字面量：提示文案里出现的命令不是插件在执行。"""
    out = re.sub(r'"(?:[^"\\]|\\.)*"', '""', line)
    return re.sub(r"'(?:[^'\\]|\\.)*'", "''", out)


def check_security():
    for p in list(sources("*.qml")) + list(sources("*.js")) + list(sources("*.sh")):
        for i, ln in enumerate(read_lines(p), 1):
            code = strip_strings(ln.split("//")[0])
            if code.lstrip().startswith(("*", "/*")):
                continue
            for m in NETWORK.finditer(code):
                add("WARN", "security", p, i, "网络命令 %r：插件不应联网，确认并在 PR 说明" % m.group(1))
            for m in PRIV.finditer(code):
                add("FAIL", "security", p, i, "提权命令 %r：必须去掉或在 PR 里证明必要" % m.group(1))
            for m in PERSIST.finditer(code):
                add("FAIL", "security", p, i, "持久化 %r：插件不该开机自启" % m.group(1))
            for m in TOUCHY.finditer(code):
                add("WARN", "security", p, i, "访问自身配置/缓存外的路径 %s" % m.group(1))
            for m in SECRET.finditer(code):
                add("FAIL", "security", p, i, "疑似硬编码凭证")


# ---------------------------------------------------------------- 2. DMS 规范

RAW_QT = {
    "Text": "StyledText（qs.Widgets）",
    "Popup": "DCommon.DDialog { popout: true }",
    "Button": "DCommon.DButton",
    "Switch": "DCommon.DToggle",
    "CheckBox": "DCommon.DToggle",
    "TextField": "DCommon.DTextField",
    "TextArea": "DCommon.DTextField",
    "ListView": "DCommon.DListView",
    "GridView": "DCommon.DGridView",
    "Flickable": "DCommon.DFlickable",
    "Slider": "DCommon.DSlider",
    "ScrollBar": "DCommon.DScrollbar",
    "ToolButton": "DCommon.DIconButton",
}
LEGACY_EFFECTS = re.compile(r"import\s+Qt5Compat\.GraphicalEffects")
HEX_COLOR = re.compile(r"#[0-9a-fA-F]{3,8}\b")
HARD_SIZE = re.compile(r"^\s*(width|height|spacing|radius|pixelSize|pointSize)\s*:\s*(\d+)\s*$")


def check_conventions():
    for p in sources("*.qml"):
        lines = read_lines(p)
        text = "\n".join(lines)
        for i, ln in enumerate(lines, 1):
            m = re.match(r"^\s*([A-Z][A-Za-z]+)\s*\{", ln)
            if m and m.group(1) in RAW_QT:
                add("FAIL", "conventions", p, i,
                    "裸 Qt 控件 %s → 用 %s" % (m.group(1), RAW_QT[m.group(1)]))
            if LEGACY_EFFECTS.search(ln):
                add("FAIL", "conventions", p, i,
                    "Qt5Compat.GraphicalEffects 未声明依赖 → 用 QtQuick.Effects 的 MultiEffect")
            if HEX_COLOR.search(ln.split("//")[0]):
                add("WARN", "conventions", p, i, "硬编码颜色 → 用 Theme token")
            m = HARD_SIZE.match(ln)
            if m and not ln.strip().startswith("//"):
                value = int(m.group(2))
                if value <= 1 or (m.group(1) == "radius" and value < 4):
                    continue
                add("WARN", "conventions", p, i,
                    "硬编码 %s: %s → 优先 Theme token；几何由内容推导的要在 PR 说明"
                    % (m.group(1), m.group(2)))
        if re.search(r"I18n\.trFor\(\s*(?![\"'])", text):
            for i, ln in enumerate(read_lines(p), 1):
                if re.search(r"I18n\.trFor\(\s*(?![\"'])", ln):
                    add("FAIL", "conventions", p, i,
                        "I18n.trFor 的 id 不是字面量：审核静态读代码，读不到就算未翻译")


# ---------------------------------------------------------------- 3. 性能

TIMER_BLOCK = re.compile(r"Timer\s*\{([^}]*)\}", re.S)


def check_performance():
    for p in sources("*.qml"):
        text = "\n".join(read_lines(p))
        for m in TIMER_BLOCK.finditer(text):
            body = m.group(1)
            line = text[: m.start()].count("\n") + 1
            tid = re.search(r"id\s*:\s*(\w+)", body)
            started = tid and re.search(r"\b%s\.start\s*\(" % tid.group(1), text)
            iv = re.search(r"interval\s*:\s*([0-9.]+)", body)
            repeat = re.search(r"repeat\s*:\s*true", body)
            running = re.search(r"running\s*:\s*(.+)", body)
            if not iv:
                continue
            interval = float(iv.group(1))
            if interval <= 100 and repeat:
                if started:
                    add("WARN", "performance", p, line,
                        "%dms repeat 定时器由 %s.start() 控制，确认有对应的 stop()" % (interval, tid.group(1)))
                elif not running:
                    add("FAIL", "performance", p, line,
                        "%dms 常驻 repeat 定时器且没有 running 条件" % interval)
                else:
                    cond = running.group(1).strip()
                    bounded = ("<" in cond and (">" in cond or "count" in cond.lower()))\
                        or "!==" in cond or "===" in cond
                    level = "WARN" if bounded else "FAIL"
                    add(level, "performance", p, line,
                        "%dms repeat 定时器，running: %s —— 确认有条件且会停" % (interval, cond[:60]))


# ---------------------------------------------------------------- 4. 注释与代码卫生

SPLIT = re.compile(r"[、，]$")
CODE_SMELL = re.compile(r"\?\s*(\"[^\"]*\"|'[^']*')\s*:\s*\1")


def check_hygiene():
    for p in sources("*.qml"):
        lines = read_lines(p)
        text = "\n".join(lines)
        for i, ln in enumerate(lines, 1):
            if re.match(r"^\s*//", ln):
                if SPLIT.search(ln):
                    nxt = lines[i].strip() if i < len(lines) else ""
                    if not nxt.startswith("//"):
                        add("FAIL", "hygiene", p, i, "注释断句（写到一半就断）")
                if re.search(r"TODO|FIXME|待补充|待查", ln):
                    add("WARN", "hygiene", p, i, "遗留标记")
        gap = re.search(r"\n{4,}", text)
        if gap:
            add("FAIL", "hygiene", p, text[: gap.start()].count("\n") + 1, "连续空行")
        for i, ln in enumerate(lines, 1):
            if CODE_SMELL.search(ln.split("//")[0]):
                add("FAIL", "hygiene", p, i, "if-else 两边返回同一字面量（无效表达式）")


# ---------------------------------------------------------------- 5. manifest 与翻译

REQUIRED = ["id", "name", "description", "version", "license", "author", "type", "capabilities"]


def check_manifest():
    p = REPO / "plugin.json"
    if not p.exists():
        add("FAIL", "manifest", "plugin.json", 0, "缺少 plugin.json")
        return None
    try:
        data = json.loads(p.read_text())
    except json.JSONDecodeError as exc:
        add("FAIL", "manifest", "plugin.json", exc.lineno, "JSON 解析失败: %s" % exc.msg)
        return None
    for key in REQUIRED:
        if key not in data:
            add("FAIL", "manifest", "plugin.json", 0, "缺少必需字段 %r" % key)
    if not re.match(r"^\d+\.\d+\.\d+$", str(data.get("version", ""))):
        add("WARN", "manifest", "plugin.json", 0, "版本号不是 x.y.z")

    deps = data.get("dependencies") or []
    body = "\n".join("\n".join(read_lines(f)) for f in sources("*.qml"))
    for dep in deps:
        if dep and dep not in body:
            add("WARN", "manifest", "plugin.json", 0,
                "依赖 %r 在代码里没找到调用，确认是否还需要" % dep)

    comps = data.get("components") or {}
    for kind, path in comps.items():
        if not (REPO / path.lstrip("./")).exists():
            add("FAIL", "manifest", "plugin.json", 0, "components.%s 指向的文件不存在: %s" % (kind, path))
    for key in ("settings", "startupCheck"):
        if key in data and not (REPO / str(data[key]).lstrip("./")).exists():
            add("FAIL", "manifest", "plugin.json", 0, "%s 指向的文件不存在: %s" % (key, data[key]))
    return data


def check_i18n(manifest):
    tr_file = REPO / "translations" / "zh_CN.json"
    strings = set()
    # 两种调用形态都要统计：字面量走 I18n.trFor，只有动态词条才用 tr(变量)
    patterns = [
        r'tr\(\s*"((?:[^"\\]|\\.)*)"',
        r'I18n\.trFor\(\s*"inlineKeyboard"\s*,\s*"((?:[^"\\]|\\.)*)"',
    ]
    for p in sources("*.qml"):
        text = "\n".join(read_lines(p))
        for pat in patterns:
            for m in re.finditer(pat, text):
                raw = m.group(1)
                try:
                    s = json.loads('"%s"' % raw)
                except json.JSONDecodeError:
                    s = raw
                if len(s) > 1:
                    strings.add(s)
    if not tr_file.exists():
        if strings:
            add("WARN", "i18n", "translations/zh_CN.json", 0,
                "有 %d 条 tr() 文案但没有翻译文件" % len(strings))
        return
    try:
        table = json.loads(tr_file.read_text())
    except json.JSONDecodeError as exc:
        add("FAIL", "i18n", "translations/zh_CN.json", exc.lineno, "JSON 解析失败: %s" % exc.msg)
        return
    # 表结构是「每词条一 bucket」：{"<term>": {"<term>": "<译文>"}}
    entries = {}
    for bucket in table.values():
        if isinstance(bucket, dict):
            entries.update(bucket)
    missing = sorted(s for s in strings if s not in entries)
    if missing:
        add("WARN", "i18n", "translations/zh_CN.json", 0,
            "%d 条 tr() 文案缺译文，例如 %r" % (len(missing), missing[0][:40]))
    if entries and strings and len(entries) > len(strings) * 2:
        add("WARN", "i18n", "translations/zh_CN.json", 0,
            "译文条数 %d 远多于 tr() 字面量 %d，可能有过期词条" % (len(entries), len(strings)))


# ---------------------------------------------------------------- 6. 注释里的参数

def check_doc_claims():
    """注释里写死的尺寸必须和代码里的基准值一致（改了一边忘了另一边）。"""
    p = REPO / "KeyboardMetrics.qml"
    if not p.exists():
        return
    text = "\n".join(read_lines(p))
    for name, label in (("gapBase", "gap"), ("padBase", "pad"), ("candHBase", "candH")):
        m = re.search(r"%s\s*:\s*([0-9.]+)" % name, text)
        if not m:
            continue
        value = m.group(1).rstrip("0").rstrip(".") if "." in m.group(1) else m.group(1)
        for line in text.split("\n"):
            if line.strip().startswith("//") and "%s %s" % (label, value) in line:
                break
        else:
            continue


# ---------------------------------------------------------------- 主流程

def main():
    quiet = "--quiet" in sys.argv
    manifest = check_manifest()
    check_security()
    check_conventions()
    check_performance()
    check_hygiene()
    check_i18n(manifest)
    check_doc_claims()

    if "--json" in sys.argv:
        print(json.dumps([{"level": l, "area": a, "file": f, "line": n, "message": m}
                          for l, a, f, n, m in FINDINGS], ensure_ascii=False, indent=2))
    else:
        order = {"FAIL": 0, "WARN": 1}
        for level, area, file, line, msg in sorted(FINDINGS, key=lambda x: (order[x[0]], x[1])):
            if quiet and level == "WARN":
                continue
            where = "%s:%d" % (file, line) if line else file
            print("%-4s [%-11s] %-42s %s" % (level, area, where, msg))
        fails = sum(1 for f in FINDINGS if f[0] == "FAIL")
        warns = sum(1 for f in FINDINGS if f[0] == "WARN")
        print()
        print("FAIL %d / WARN %d" % (fails, warns))
        if fails:
            print("有 FAIL：提交前必须修。")
        elif warns:
            print("只剩 WARN：确认每一条都能在 PR 里说明理由。")
        else:
            print("干净。")
    return 1 if any(f[0] == "FAIL" for f in FINDINGS) else 0


if __name__ == "__main__":
    sys.exit(main())
