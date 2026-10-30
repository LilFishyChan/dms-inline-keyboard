#!/usr/bin/env python3
"""act 块：右上角动作槽 / 顶部导航 / 磁贴 / 最小化 / 开关。"""

import re
import time

from . import common as c


def actions():
    print("== act 动作槽 / 导航 / 磁贴 ==")
    # 右上角动作槽：默认是浮动开关
    r = c.ipc("debugTap", "slot", "", 0)
    c.check("点右上角动作槽", "TAP:slot" in r, r)
    time.sleep(0.6)
    c.check("浮动开关生效", "isFloat=1" in c.diag(), c.diag()[:150])
    r = c.ipc("debugTap", "slot", "", 0)
    c.check("再点槽", "TAP:slot" in r, r)
    time.sleep(0.6)
    c.check("回到停靠", "isFloat=0" in c.diag(), c.diag()[:150])

    # 顶部导航键进功能列表 → 点「透明度」磁贴 → 同一个键确认
    r = c.ipc("debugTap", "nav", "", 0)
    c.check("点导航键", "TAP:nav" in r, r)
    time.sleep(0.5)
    c.check("导航进功能列表", "mode=functions" in c.diag(), c.diag()[:150])
    r = c.ipc("debugTap", "action", "opacity", 0)
    c.check("点磁贴（透明度）", "action:opacity" in r, r)
    time.sleep(0.6)
    c.check("透明度面板打开", "mode=transparency" in c.diag(), c.diag()[:150])
    c.ipc("debugTap", "nav", "", 0)
    time.sleep(0.5)
    c.check("确认键回键盘页", "mode=keys" in c.diag(), c.diag()[:150])


def minimize():
    print("== act 最小化 ==")
    c.ipc("debugTap", "nav", "", 0)
    time.sleep(0.5)
    r = c.ipc("debugTap", "action", "minimize", 0)
    c.check("点最小化磁贴", "action:minimize" in r, r)
    time.sleep(0.8)
    c.check("最小化后 open 仍为真", "open=true" in c.diag(), c.diag()[:150])
    c.check("min 标记置位", "min=1" in c.diag(), c.diag()[:150])
    c.ipc("open")
    time.sleep(1.2)
    c.check("恢复后不再是 min", "min=0" in c.diag(), c.diag()[:150])


def openclose():
    print("== act 关闭再打开 ==")
    c.ipc("setPage", "page2")
    time.sleep(0.3)
    c.ipc("close")
    time.sleep(0.8)
    c.check("关闭后 open=false", "open=false" in c.diag(), c.diag()[:150])
    c.ipc("open")
    time.sleep(2.0)
    c.check("重开后 open=true", "open=true" in c.diag(), c.diag()[:150])
    c.check("重开后落在合法页", re.search(r"page=page[12]", c.diag()) is not None,
            c.diag()[:150])
    c.ipc("setPage", "page1")
    time.sleep(0.3)
