#!/usr/bin/env python3
"""env 块：设置持久化 + 设置页冒烟。

这一块必须重启 dms（两次），所以单跑一次要十几秒，别放进快循环。
设置页是按需实例化的，但 dms 重启时也会预实例化一次 ——
所以「设置页有没有 QML 错误」能靠重启 + 查 journal 抓，不用人去点。
"""

import re
import time

from . import common as c


def _journal_hits(since_epoch):
    """本次运行之后 journal 里跟本插件相关的错误/警告。"""
    r = c.shell(["bash", "-c",
                 "journalctl --user -u dms --since @%d 2>/dev/null "
                 "| grep -iE 'InlineKeyboard(Settings)?\\.qml|is not a type|component error|Binding loop' "
                 "| grep -v 'CloseProgramDialog'" % int(since_epoch)])
    return [ln for ln in (r.stdout or "").splitlines() if ln.strip()]


def persist():
    """设置改写 → 重启 → 读回一致；然后还原再重启一次。"""
    print("== env 设置持久化 ==")
    key = "bgOpacity"
    orig = c.load_settings().get(key, 100)
    tmp = 88 if orig != 88 else 91

    c.patch_setting(key, tmp)
    c.check("重启 dms", c.set_debug_mode(True), "loaded 超时")
    c.check("插件重启后 loaded", c.plugin_status() == "loaded", c.plugin_status())
    c.check("设置值重启后保持（%s=%s）" % (key, tmp),
            c.load_settings().get(key) == tmp, c.load_settings().get(key))

    c.patch_setting(key, orig)
    c.set_debug_mode(True)
    c.check("设置已还原（%s=%s）" % (key, orig),
            c.load_settings().get(key) == orig, c.load_settings().get(key))


def smoke():
    """重启一次，确认设置页 / 插件没有 QML 错误，并检查基本可用。"""
    print("== env 冒烟（设置页 + loaded）==")
    started = time.time()
    c.check("重启 dms", c.set_debug_mode(True), "loaded 超时")
    time.sleep(1.5)

    c.check("插件 loaded", c.plugin_status() == "loaded", c.plugin_status())
    c.check("调试 IPC 可用", c.ipc("debugPanel") != "dev mode off", c.ipc("debugPanel")[:80])

    hits = _journal_hits(started)
    c.check("本次重启没有本插件的 QML 错误", not hits,
            "\n".join(hits[:3]) if hits else "")

    c.ipc("open")
    time.sleep(1.5)
    c.check("键盘能打开", "open=true" in c.diag(), c.diag()[:150])
    c.check("fcitx 桥有状态字段", "socket=" in c.diag(), c.diag()[:150])
