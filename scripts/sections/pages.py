#!/usr/bin/env python3
"""pages 块：表情页（进页 / 返回 / 符号段 / 分类 chip）。"""

import time

from . import common as c


def emoji():
    print("== pages 表情页 ==")
    r = c.ipc("setPage", "emoji")
    c.check("切到表情页", r.endswith("emoji"), r)
    c.check("diag 显示表情页", "page=emoji" in c.diag(), c.diag()[:150])
    c.ipc("setPage", "page1")
    time.sleep(0.4)

    # 表情键（icon=mood）是普通跳转，别被第二页的状态机吃掉
    r = c.ipc("debugTap", "key", "mood", 40)
    c.check("点表情键", "TAP:mood" in r, r)
    time.sleep(0.5)
    c.check("表情键进表情页（不是第二页）", "page=emoji" in c.diag(), c.diag()[:150])

    # 表情页返回键（X）走的也是 page 键：必须回第一页，不能被循环成第二页
    c.ipc("debugKey", "page", "page1")
    time.sleep(0.5)
    c.check("返回键回到第一页", "page=page1" in c.diag(), c.diag()[:150])

    # 符号段：切过去内容要变（分类条只在 emoji 段有）
    r = c.ipc("setEmojiFilter", "symbols", "all")
    c.check("切到符号段", "symbol" in r, r)

    # 分段按钮的 currentIndex 和 controller 状态必须一致：
    # 点过之后 currentIndex 的绑定会被 QML 打断，靠 Connections 兜底同步
    seg = c.ipc("debugEmojiSegment")
    c.check("符号段按钮索引 = 1", "segment=symbol" in seg and "index=1" in seg, seg)
    c.ipc("setEmojiFilter", "emoji", "all")
    time.sleep(0.4)
    seg = c.ipc("debugEmojiSegment")
    c.check("表情段按钮索引 = 0", "segment=emoji" in seg and "index=0" in seg, seg)

    # 真实点击分段按钮：DButtonGroup 单选只发 selectionChanged，
    # 选中态要自己维护，这里锁住「点得动」这一点
    r = c.ipc("debugTapEmojiSegment", "1")
    c.check("点符号段按钮", "emojiSeg:1" in r, r)
    time.sleep(0.5)
    seg = c.ipc("debugEmojiSegment")
    c.check("点完切到符号段", "segment=symbol" in seg and "index=1" in seg, seg)
    r = c.ipc("debugTapEmojiSegment", "0")
    c.check("点回表情段按钮", "emojiSeg:0" in r, r)
    time.sleep(0.5)

    # 分类 chip 走真实点击
    r = c.ipc("debugTap", "emojiCat", "smileys", 0)
    c.check("点分类 chip", "emojiCat:smileys" in r, r)

    c.ipc("setPage", "page1")
    c.check("表情页能回主键区", "page=page1" in c.diag(), c.diag()[:150])
