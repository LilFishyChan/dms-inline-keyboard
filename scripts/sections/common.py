#!/usr/bin/env python3
"""验收脚本的公共部分：IPC 调用、断言、布局数据加载、dev 环境开关。

布局数据（期望值）只从 layouts/*.js 和 plugin_settings.json 读，
不从插件运行时反推 —— 否则测的是「实现和实现一致」。
"""

import json
import subprocess
import sys
import time
from pathlib import Path

PLUGIN = "inlineKeyboard"
REPO = Path(__file__).resolve().parents[2]
SETTINGS = Path.home() / ".config/dms/plugin_settings.json"
QMLCACHE = Path.home() / ".cache/quickshell/qmlcache"

failures = []
stats = {"total": 0, "failed": 0}


def shell(cmd, cwd=None, timeout=30):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)


def ipc(fn, *args):
    """调用插件自己的 IPC。"""
    r = shell(["dms", "ipc", "call", PLUGIN, fn, *[str(a) for a in args]])
    return (r.stdout or "").strip()


def plugin_status():
    r = shell(["dms", "ipc", "call", "plugins", "status", PLUGIN])
    return (r.stdout or "").strip()


def diag():
    return ipc("diag")


def check(name, ok, detail=""):
    stats["total"] += 1
    if ok:
        print("  ok   " + name)
    else:
        stats["failed"] += 1
        failures.append(name)
        print("  FAIL " + name + (" — " + str(detail).replace("\n", " | ")[:300] if detail else ""))
    return ok


# ---- 设置 ----

def load_settings():
    try:
        return json.loads(SETTINGS.read_text()).get(PLUGIN, {})
    except Exception:
        return {}


def patch_setting(key, value):
    data = json.loads(SETTINGS.read_text())
    data.setdefault(PLUGIN, {})[key] = value
    SETTINGS.write_text(json.dumps(data, ensure_ascii=False, indent=2))


def restart_dms():
    shell(["rm", "-rf", str(QMLCACHE)])
    shell(["systemctl", "--user", "restart", "dms"])
    # 等 dms 把插件挂回来
    for _ in range(40):
        time.sleep(0.5)
        if "loaded" in plugin_status():
            return True
    return False


def set_debug_mode(on):
    """调试模式走设置项（设置页那个开关），不依赖环境变量。"""
    patch_setting("debugMode", on)
    return restart_dms()


def ensure_full_keyboard():
    """确保是完整键盘而不是最小化圆钮。

    lastMode 记在 state 里后，关一次最小化的键盘、再 open 会真的恢复成最小化，
    卡片不渲染 → 读不到键表。任何要读布局的块都先过这一步。
    """
    if "min=1" in diag():
        ipc("debugQuickAction", "minimize")
        time.sleep(1.2)
    return "min=0" in diag()


def ensure_card():
    """确认 activeCard 真的在（键盘开着 ≠ 卡片渲染了）。

    keys 块连点几百下之后，后续块经常拿到 no-card；这一步把它拉回可用状态。
    """
    if "no-card" not in ipc("debugPanel"):
        return True
    for _ in range(3):
        ipc("open")
        time.sleep(2.0)
        ensure_full_keyboard()
        if "no-card" not in ipc("debugPanel"):
            return True
    return False


def ensure_dev():
    """调试模式已经开着、插件也 loaded 就别重启 —— 重启会打断用户正在做的事。

    脚本不负责部署；QML 改动该重载时是部署那一步的事，这里只管「能不能用」。
    """
    if load_settings().get("debugMode") and plugin_status() == "loaded":
        return True
    return set_debug_mode(True)


# ---- 布局数据：期望值的唯一来源 ----

_NODE_LOADER = r"""
const fs = require('fs');
function load(file) {
  let src = fs.readFileSync(file, 'utf8');
  src = src.replace(/^[\s\uFEFF]*\.pragma\s+library\s*/, '');
  const m = { exports: {} };
  new Function('module', 'exports', src)(m, m.exports);
  return m.exports;
}
const out = { rows: load('layouts/phone.js').rows };
try { out.emoji = load('layouts/emoji.js'); } catch (e) { out.emoji = null; }
console.log(JSON.stringify(out));
"""

_layout_cache = None


def load_layout():
    """layouts/phone.js + emoji.js 的原始数据（node 剥掉 .pragma library 再求值）。"""
    global _layout_cache
    if _layout_cache is None:
        r = shell(["node", "-e", _NODE_LOADER], cwd=str(REPO))
        if r.returncode != 0:
            raise SystemExit("读布局数据失败: " + (r.stderr or "")[:400])
        _layout_cache = json.loads(r.stdout)
    return _layout_cache


def page_keys(page):
    """某一页展开后的键列表（含 spacer，顺序与渲染一致）。"""
    rows = load_layout()["rows"].get(page)
    if rows is None:
        return []
    return [k for row in rows for k in row]


def esc_swap_enabled():
    return bool(load_settings().get("escSwap", False))


# ---- 渲染侧：插件报告的当前页键表 ----

def render_keys(page):
    """切到该页后读 debugKeyList：返回 [{index,label,code,kind,fn_label,has_shift}]。

    这一份是「渲染出来的」，期望值从 page_keys() 算，两边独立。
    """
    ipc("setPage", page)
    time.sleep(0.5)
    raw = ipc("debugKeyList")
    out = []
    for line in (raw or "").splitlines():
        parts = line.split("|")
        if len(parts) < 6:
            continue
        out.append({
            "index": int(parts[0]),
            "label": parts[1],
            "code": int(parts[2]),
            "kind": parts[3],
            "fn_label": parts[4],
            "has_shift": parts[5] == "1",
        })
    return out


# ---- 干跑记录 ----

def dry_run(on):
    return ipc("debugSetDryRun", "true" if on else "false")


def clear_injected():
    return ipc("debugClearInjected")


def injected():
    """解析 debugInjected：头一行 INJECTED[n]:，之后一条记录一行 标签/类型/选路/键码/m修饰位。"""
    raw = ipc("debugInjected") or ""
    if not raw.startswith("INJECTED["):
        return []
    out = []
    for line in raw.split("\n")[1:]:
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        out.append({
            "label": parts[0],
            "kind": parts[1],
            "route": parts[2],
            "code": int(parts[3]) if parts[3].lstrip("-").isdigit() else -1,
            "mods": parts[4],
        })
    return out


def journal_errors(since_ts):
    """本次运行期间本插件在 journal 里的 qml 级错误（其它插件的不算）。"""
    r = shell(["journalctl", "--user", "-u", "dms", "--since", "@%d" % int(since_ts - 5)])
    bad = []
    for line in (r.stdout or "").splitlines():
        low = line.lower()
        if "inlinekeyboard" not in low and "inline keyboard" not in low:
            continue
        if "deprecation" in low:
            continue
        if ("error qml" in low or "typeerror" in low or "binding loop" in low
                or "is not a type" in low):
            bad.append(line.strip())
    return bad


def summary():
    print("\n共 %d 项断言，%d 项失败" % (stats["total"], stats["failed"]))
    if stats["failed"] == 0:
        print("全部通过")
        return 0
    print("失败项：" + ", ".join(failures))
    return 1


# ---- 事件拦截守卫 ----

ADDON_LOG = Path("/run/user/1000/inline-keyboard-addon.log")


def addon_key_count():
    """addon 真正发给应用的键数：干跑期间这个数必须一动不动。"""
    try:
        return ADDON_LOG.read_text(errors="ignore").count("key sent")
    except Exception:
        return -1


def injected_count():
    return len(injected())


def guard_dry_run(letter_index, repeat_index):
    """真实点击前必须先过这一关，证明干跑真的挡住了东西。

    连发点击曾经把 release 吃掉，可重复键（Backspace 等）的 holdTimer 停不下来，
    400ms 后每 60ms 往外发一次 —— 输入法就是那么被打崩的。所以第二段专门测它。
    """
    print("== 守卫：确认事件拦截生效 ==")
    ok = True
    r = dry_run(True)
    if "now=on" not in r:
        check("守卫: 干跑真的开启了", False, r)
        raise SystemExit("守卫未通过：干跑没设上（%r），中止，一个键都没点" % r)
    ok &= check("守卫: 干跑真的开启了", True, r)
    clear_injected()
    base_keys = addon_key_count()
    opened = "open=true" in diag()
    ok &= check("守卫: 键盘是打开的", opened, diag()[:150])
    if not opened:
        dry_run(False)
        raise SystemExit("守卫未通过：键盘没打开，先 open 再来")

    # 1) 普通字母键：只该产生一条干跑记录，应用侧一条都不该收到
    r = ipc("debugTap", "keyAt", letter_index, 40)
    ok &= check("守卫: 字母键点击被受理", "TAP:index" in r, r)
    time.sleep(0.4)
    n1 = injected_count()
    ok &= check("守卫: 点字母键 → 干跑记录 1 条", n1 == 1, "记录 %d" % n1)
    ok &= check("守卫: 点字母键 → 没有真实输入", addon_key_count() == base_keys,
                "addon %d → %d" % (base_keys, addon_key_count()))

    # 2) 可重复键按住 40ms（远低于 400ms 长按阈值）：不许启动重复
    r = ipc("debugTap", "keyAt", repeat_index, 40)
    ok &= check("守卫: Backspace 点击被受理", "TAP:index" in r, r)
    time.sleep(0.9)
    n2 = injected_count()
    ok &= check("守卫: 点 Backspace → 干跑记录 2 条", n2 == 2, "记录 %d" % n2)
    ok &= check("守卫: 长按重复没有启动", n2 == 2, "记录 %d（>2 说明在重复发键）" % n2)
    ok &= check("守卫: 点 Backspace → 没有真实输入", addon_key_count() == base_keys,
                "addon %d → %d" % (base_keys, addon_key_count()))
    ok &= check("守卫: 键盘仍然打开", "open=true" in diag(), diag()[:150])

    clear_injected()
    dry_run(False)
    if not ok:
        raise SystemExit("守卫未通过：事件拦截不可靠，中止（没有继续点任何键）")
    print("  守卫通过：干跑拦得住，长按重复也没失控")
    return True
