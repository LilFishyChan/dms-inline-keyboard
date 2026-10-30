#!/usr/bin/env python3
"""分块验收：模拟用户流程的那一层（纯逻辑走 node --test，不在这里）。

用法：
    python3 scripts/acceptance.py               # 全量（8 块）
    python3 scripts/acceptance.py keys          # 只跑键位
    python3 scripts/acceptance.py keys drag      # 跑两块
    python3 scripts/acceptance.py --list         # 列出块

每块自己负责收尾（还原设置 / 清候选 / 回第一页），所以可以任意组合、任意顺序。
真正的按键点击前都会先跑守卫（common.guard_dry_run）证明干跑拦得住。
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sections import (act, cand, common as c, drag, env, geo, keys, pages,
                      settings)

BLOCKS = {
    "keys": ("键位遍历 / Fn·Shift 层 / 页面键 / 修饰键 / 干跑",
             [keys.page1, keys.page2, keys.layers, keys.pages, keys.mods, keys.dry]),
    "cand": ("候选条 / 列表 / 侧键 / 地球键",
             [cand.candidates, cand.sides, cand.globe]),
    "pages": ("表情页 / 符号段 / 分类 chip", [pages.emoji]),
    "act": ("动作槽 / 导航 / 磁贴 / 最小化 / 开关",
            [act.actions, act.minimize, act.openclose]),
    "geo": ("尺寸 / 透明度 / 浮动位置", [geo.geometry]),
    "drag": ("点击 / 长按 / 拖动", [drag.drag]),
    "settings": ("设置项临时改值 → 生效 → 还原", [settings.settings]),
    "env": ("设置持久化 / 重启冒烟", [env.persist, env.smoke]),
}

ORDER = ["keys", "cand", "pages", "act", "geo", "drag", "settings", "env"]


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("-")]

    if "--list" in argv:
        for name in ORDER:
            desc, fns = BLOCKS[name]
            print("%-9s %s（%d 个子块）" % (name, desc, len(fns)))
        return 0

    picked = args or ORDER
    unknown = [a for a in picked if a not in BLOCKS]
    if unknown:
        print("未知块：%s" % ", ".join(unknown))
        print("可用：%s" % ", ".join(ORDER))
        return 2

    started = time.time()
    was_open = "open=true" in c.diag()
    orig_debug = c.load_settings().get("debugMode", False)

    print("== 准备：确保调试模式可用 ==")
    if not c.ensure_dev():
        print("  FAIL  插件没起来（loaded 超时）")
        return 1
    c.check("插件 loaded", c.plugin_status() == "loaded")
    c.check("调试 IPC 可用", c.ipc("debugPanel") != "dev mode off")
    if "open=true" not in c.diag():
        c.ipc("open")
        time.sleep(2)
    c.check("键盘能打开", "open=true" in c.diag(), c.diag()[:120])
    # 上次可能停在最小化（lastMode 记在 state 里），先恢复成完整键盘，否则读不到键表
    c.check("键盘是完整形态（非最小化）", c.ensure_full_keyboard(), c.diag()[:120])

    for name in picked:
        desc, fns = BLOCKS[name]
        print("\n### %s —— %s" % (name, desc))
        # 上一块可能把卡片点没了（no-card），每块开始前确认一次
        c.check("%s: 卡片就绪" % name, c.ensure_card(), c.ipc("debugPanel")[:120])
        for fn in fns:
            fn()

    print("\n== 收尾 ==")
    if was_open:
        c.ipc("open")
    else:
        c.ipc("close")
    time.sleep(1.2)
    c.check("键盘回到进入前的开合状态", ("open=true" in c.diag()) == was_open)

    hits = c.journal_errors(started)
    c.check("本次运行没有本插件的 qml 级错误", not hits, "\n".join(hits[:3]))

    if not orig_debug:
        c.patch_setting("debugMode", False)
    return c.summary()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
