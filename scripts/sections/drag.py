#!/usr/bin/env python3
"""drag 块：点击 / 长按 / 拖动。

走的都是控件自己的 pressAt → releaseAt → clickAt 和卡片的 endDrag，
和手指是同一条路径；不经过系统输入、不移动鼠标。
"""

import re
import time

from . import common as c


def drag():
    print("== drag 点击 / 长按 / 拖动 ==")
    # 点击：页面键（只切页，不发字符，零副作用）
    r = c.ipc("debugTap", "key", "layers", 40)
    c.check("注入点击（页面键）", "TAP:layers" in r, r)
    time.sleep(0.5)
    c.check("点击后切到第二页", "page=page2" in c.diag(), c.diag()[:150])
    time.sleep(0.6)          # 拉开间隔，避免被判成双击锁定
    r = c.ipc("debugTap", "key", "layers", 40)
    c.check("再点一次", "TAP:layers" in r, r)
    time.sleep(0.5)
    c.check("回第一页", "page=page1" in c.diag(), c.diag()[:150])

    # 长按：noLock 档按住 Ctrl 800ms，按住期间必须处于激活态
    c.ipc("setModifierMode", "noLock")
    time.sleep(0.3)
    r = c.ipc("debugTap", "key", "Ctrl", 800)
    c.check("注入长按（800ms）", "TAP:Ctrl" in r, r)
    c.check("长按期间修饰键激活", "ctrl=1" in c.diag(), c.diag()[:150])
    time.sleep(1.2)
    c.check("松开后归零", "ctrl=0" in c.diag(), c.diag()[:150])
    c.ipc("setModifierMode", "doubleTapLock")
    time.sleep(0.3)

    # 拖动：拖到卡片外再松手，落点必须判为无效（不改顺序）
    # 坐标用大正数：负数会被 CLI 当成 flag 解析
    r = c.ipc("debugDrag", 0, 99999, 99999)
    c.check("注入拖动起点", "INLINE_KEYBOARD_DRAG" in r, r)
    c.check("卡片外判为无效落点", "listIndex=-1" in r and "barIndex=-1" in r, r)
    r = c.ipc("debugDrop")
    c.check("松手不崩", r.startswith("INLINE_KEYBOARD_DROPPED"), r)
    c.check("拖动后插件仍 loaded", c.plugin_status() == "loaded", c.plugin_status())

    # 固定栏拖动同样要能起手、能落到无效点
    r = c.ipc("debugDragFromBar", 0, 99999, 99999)
    c.check("固定栏拖动起手", "INLINE_KEYBOARD" in r, r)
    c.ipc("debugDrop")
    c.check("固定栏拖完插件仍 loaded", c.plugin_status() == "loaded", c.plugin_status())
