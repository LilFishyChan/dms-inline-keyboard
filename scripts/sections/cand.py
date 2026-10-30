#!/usr/bin/env python3
"""cand 块：候选条 / 候选列表 / 地球键。

候选用 debugCand 注入假数据（不依赖真实输入法），
所以任何机器都能跑；真实 fcitx 返回结构变没变它抓不到，那部分留手测。
"""

import re
import time

from . import common as c

# 词数要足够多，否则全塞进顶栏、列表页剩 0 项（顶栏和列表是同一份数据的两段）
WORDS = ("一一,二二,三三,哈哈,测试词,候选一,候选二,候选三,候选四,候选五,"
         "长长长长词条,短,中文字,还有别的,七八九,十个字,十一,十二,十三,十四,"
         "十五,十六,十七,十八,十九,二十,二十一,二十二,二十三,二十四")
WORD_COUNT = 30


def candidates():
    print("== cand 候选条 / 列表 ==")
    # 注意：check 的 detail 参数每次都会求值，别在里面放有副作用的调用
    # （曾经把 debugCand("") 写进 detail，结果刚注入的候选被自己清掉了）
    r = c.ipc("debugCand", WORDS)
    c.check("注入假候选", r.startswith(str(WORD_COUNT)), r)
    c.ipc("open")
    time.sleep(0.5)

    # 顶栏数量要在展开之前读：列表页一展开，顶栏就让位清空了
    m = re.search(r"bar=(\d+)", c.diag())
    n_bar = int(m.group(1)) if m else -1
    c.check("顶栏读得到数量", n_bar >= 0, c.diag()[:150])

    r = c.ipc("debugTap", "expand", "", 0)
    c.check("点展开按钮（真实路径）", "candExpand" in r, r)
    time.sleep(0.6)
    c.check("候选列表已展开", "candListOpen=true" in c.diag(), c.diag()[:150])

    panel = c.ipc("debugPanel")
    m2 = re.search(r"slice=(\d+)", panel)
    if m2 and n_bar >= 0:
        n_list = int(m2.group(1))
        c.check("顶栏只装一部分", 0 < n_bar < WORD_COUNT, "n=%d" % n_bar)
        c.check("顶栏 + 列表 = 全部候选", n_bar + n_list == WORD_COUNT,
                "%d + %d != %d" % (n_bar, n_list, WORD_COUNT))
    else:
        c.check("顶栏 / 列表切分字段齐全", False, panel[:150])

    time.sleep(0.8)
    panel = c.ipc("debugPanel")
    c.check("列表页有内容", "items=0" not in panel, panel)
    c.check("列表页内容高 > 0", "contentH=0" not in panel, panel)
    c.check("列表页贴住可用宽度", "listW=" in panel, panel)

    c.ipc("debugTap", "expand", "", 0)
    c.ipc("debugCand", "")
    time.sleep(0.5)


def sides():
    """候选列表右侧的上下翻 / 退格 / 确认键（走真实点击）。"""
    print("== cand 列表侧键 ==")
    c.ipc("debugCand", WORDS)
    c.ipc("open")
    time.sleep(0.5)
    c.ipc("debugTap", "expand", "", 0)
    time.sleep(0.7)

    # 只有 30 个候选时列表刚好 3 行装得下（contentH == 可视高度），翻页键本来就不该动，
    # 所以这里断言「点得动 + 面板之后仍然正常」，不做滚动量的断言。
    r = c.ipc("debugTap", "side", "down", 0)
    c.check("点下翻键", "candSide:down" in r, r)
    time.sleep(0.6)
    c.check("下翻后面板仍正常", "open=true" in c.ipc("debugPanel"), c.ipc("debugPanel"))

    r = c.ipc("debugTap", "side", "up", 0)
    c.check("点上翻键", "candSide:up" in r, r)
    time.sleep(0.6)
    c.check("上翻后面板仍正常", "open=true" in c.ipc("debugPanel"), c.ipc("debugPanel"))

    r = c.ipc("debugTap", "expand", "", 0)
    c.check("再点收起列表", "candExpand" in r, r)
    time.sleep(0.5)
    c.check("列表已收起", "candListOpen=false" in c.diag(), c.diag()[:150])

    c.ipc("debugCand", "")
    time.sleep(0.4)


def globe():
    """地球键：循环切换输入法，最后必须回到起点。"""
    print("== cand 地球键 ==")
    m = re.search(r"im=([^/ ]+)", c.diag())
    before = m.group(1) if m else ""
    if not before:
        c.check("读得到当前输入法", False, c.diag()[:150])
        return

    r = c.ipc("debugTap", "bottom", "lang", 0)
    c.check("点地球键", "bottom:lang" in r, r)
    time.sleep(0.5)
    # 一圈最多 imRows 次；转回起点为止，别把输入法留在别的项上
    for _ in range(5):
        if ("im=" + before) in c.diag():
            break
        c.ipc("debugTap", "bottom", "lang", 0)
        time.sleep(0.35)
    c.check("循环能回到起点", ("im=" + before) in c.diag(),
            before + " / " + c.diag()[:120])
