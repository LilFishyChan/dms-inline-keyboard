#!/usr/bin/env python3
"""geo 块：键盘尺寸 / 透明度 / 浮动位置 —— 读得到、写得进、还原得回去。

三个写入都是落盘项，所以每条都要「设 → 读回 → 还原」，
跑完不许把用户设置改掉。
"""

import re
import time

from . import common as c


def geometry():
    print("== geo 几何 / 透明度 / 位置 ==")
    g0 = c.ipc("debugGeometry")
    mg = re.search(r"w=(\d+) h=(\d+).*bg=(\d+) key=(\d+)", g0)
    ms = re.search(r"saved=(\d+)x(\d+)", g0)
    if not (mg and ms):
        c.check("几何字段齐全", False, g0)
        return

    w0, h0, bg0, key0 = (int(x) for x in mg.groups())
    saved_w, saved_h = int(ms.group(1)), int(ms.group(2))
    c.check("读得到实际尺寸", w0 > 0 and h0 > 0, g0)
    c.check("读得到落盘尺寸", saved_w > 0 and saved_h > 0, g0)

    # 临时尺寸：和目标值不同才有意义
    tw = 900 if w0 != 900 else 880
    c.ipc("debugSetSize", tw, 400)
    time.sleep(0.7)
    g1 = c.ipc("debugGeometry")
    c.check("设尺寸 → 实际尺寸跟着变", ("w=%d" % tw) in g1, g1)
    c.ipc("debugSetSize", saved_w, saved_h)
    time.sleep(0.7)
    g2 = c.ipc("debugGeometry")
    c.check("尺寸已还原",
            ("w=%d" % w0) in g2 and ("saved=%dx%d" % (saved_w, saved_h)) in g2, g2)

    c.ipc("debugSetOpacity", 88, 92)
    time.sleep(0.4)
    g3 = c.ipc("debugGeometry")
    c.check("设透明度生效", "bg=88 key=92" in g3, g3)
    c.ipc("debugSetOpacity", bg0, key0)
    time.sleep(0.4)
    g4 = c.ipc("debugGeometry")
    c.check("透明度已还原", ("bg=%d key=%d" % (bg0, key0)) in g4, g4)

    # 浮动位置：切浮动 → 设位置 → 还原 → 切回停靠
    c.ipc("debugTap", "slot", "", 0)
    time.sleep(0.9)
    gp = c.ipc("debugGeometry")
    mp = re.search(r"pos=(-?\d+),(-?\d+)", gp)
    if "float=1" not in gp or not mp:
        c.check("浮动位置可读", False, gp)
        return
    px0, py0 = int(mp.group(1)), int(mp.group(2))
    c.check("浮动位置可读", True, gp)
    if px0 >= 0 and py0 >= 0:
        c.ipc("debugSetPosition", 200, 300)
        time.sleep(0.6)
        g5 = c.ipc("debugGeometry")
        c.check("设位置生效", "x=200 y=300" in g5, g5)
        c.ipc("debugSetPosition", px0, py0)
        time.sleep(0.5)
        c.check("位置已还原", ("pos=%d,%d" % (px0, py0)) in c.ipc("debugGeometry"))
    else:
        c.check("位置没有历史记录，只验证可读", True)
    c.ipc("debugTap", "slot", "", 0)
    time.sleep(0.9)
    c.check("回到停靠", "float=0" in c.ipc("debugGeometry"), c.ipc("debugGeometry"))
