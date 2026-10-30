#!/usr/bin/env python3
"""settings 块：临时把设置改掉，验证行为真的跟着变，再还原。

走 debugSetSetting → PluginService.savePluginData（和设置页同一条路），
写完 daemon 的 onPluginDataChanged → reloadSettings 立刻生效，不用重启。
每一项都必须还原，否则会改掉用户设置。
"""

import time

from . import common as c


def _set(key, value):
    return c.ipc("debugSetSetting", key, value)


def _restore(key, value):
    if isinstance(value, bool):
        _set(key, "true" if value else "false")
    else:
        _set(key, str(value))
    time.sleep(0.35)


def settings():
    print("== settings 设置项生效 ==")
    s = c.load_settings()

    # 1. escSwap：~ 键和 Esc 互换（渲染侧最先看得到）
    orig = s.get("escSwap", False)
    _set("escSwap", "false")
    time.sleep(0.45)
    k0 = c.render_keys("page1")[0]
    c.check("escSwap 关 → ~ 键是 ` / 41",
            k0["label"] == "`" and k0["code"] == 41, k0)
    _set("escSwap", "true")
    time.sleep(0.45)
    k0 = c.render_keys("page1")[0]
    c.check("escSwap 开 → ~ 键变 Esc / 1",
            k0["label"] == "Esc" and k0["code"] == 1, k0)
    _restore("escSwap", orig)

    # 2. dockFillWidth：铺满宽度
    orig = s.get("dockFillWidth", False)
    _set("dockFillWidth", "true")
    time.sleep(0.5)
    c.check("dockFillWidth 开 → dockFill=1", "dockFill=1" in c.diag(), c.diag()[:150])
    _set("dockFillWidth", "false")
    time.sleep(0.5)
    c.check("dockFillWidth 关 → dockFill=0", "dockFill=0" in c.diag(), c.diag()[:150])
    _restore("dockFillWidth", orig)

    # 3. specialKeyStyle：icon ↔ text（diag 里是 special=icon / special=full）
    orig = s.get("specialKeyStyle", "icon")
    _set("specialKeyStyle", "text")
    time.sleep(0.5)
    c.check("specialKeyStyle=text → special=full", "special=full" in c.diag(), c.diag()[:150])
    _set("specialKeyStyle", "icon")
    time.sleep(0.5)
    c.check("specialKeyStyle=icon → special=icon", "special=icon" in c.diag(), c.diag()[:150])
    _restore("specialKeyStyle", orig)

    # 4. slotActionId：右上角槽换成最小化，点它就该最小化
    orig = s.get("slotActionId", "float")
    _set("slotActionId", "minimize")
    time.sleep(0.5)
    r = c.ipc("debugTap", "slot", "", 0)
    c.check("槽换成 minimize 后点槽", "TAP:slot" in r, r)
    time.sleep(0.8)
    c.check("点槽执行的是最小化", "min=1" in c.diag(), c.diag()[:150])
    c.ipc("open")
    time.sleep(1.2)
    # lastMode 记着 minimized，open 会真的恢复成最小化 → 显式切回完整键盘
    c.check("恢复后不再是 min", c.ensure_full_keyboard(), c.diag()[:150])
    _restore("slotActionId", orig)

    # 5. keyOpacity / bgOpacity：改完 debugGeometry 要读得到
    bg0 = s.get("bgOpacity", 100)
    _set("bgOpacity", "61")
    time.sleep(0.4)
    c.check("bgOpacity 设 61 → debugGeometry 读得到",
            "bg=61" in c.ipc("debugGeometry"), c.ipc("debugGeometry"))
    _restore("bgOpacity", bg0)

    # 收尾：确认所有设置都回到原值
    now = c.load_settings()
    drift = [k for k in ("escSwap", "dockFillWidth", "specialKeyStyle",
                         "slotActionId", "bgOpacity")
             if now.get(k) != s.get(k)]
    c.check("所有被改过的设置已还原", not drift,
            ", ".join("%s: %s→%s" % (k, s.get(k), now.get(k)) for k in drift))
