// 调试 / 测试用的 IPC 实现：只读诊断、状态注入、模拟点击 / 长按 / 拖动。
// 调试模式打开时由 InlineKeyboardDaemon 用 Loader 实例化；关掉时这个文件根本不会被加载。
// 这里不包含任何「执行任意命令」的能力。

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins
import "modifiers.js" as Modifiers
import "layouts/resize.js" as Resize

Item {
    id: debugIpc

    // 宿主 daemon：属性 / 函数全部从这里取
    property var controller: null

    function debugCardHeight(): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "INLINE_KEYBOARD_H:-1"
        // win 的高度才决定 exclusiveZone；card 自己没有 implicitHeight
        const win = controller.floating ? controller.floatingLoaderItem
                                  : controller.dockedLoaderItem
        return "INLINE_KEYBOARD_H:card=" + Math.round(card.height)
               + ":win=" + (win ? Math.round(win.implicitHeight) : "-")
               + ":zone=" + (win ? Math.round(win.exclusiveZone) : "-")
               + ":kbHeight=" + Math.round(controller.kbHeight)
               + ":page=" + controller.page + ":mode=" + controller.mode
    }

    // 调试用：表情页的段 / 分类（写的是卡片上的属性，和点分类条效果一致）
    function setEmojiFilter(segment: string, category: string): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "INLINE_KEYBOARD_EMOJI:no-card"
        if (segment)
            card.emojiSegment = segment
        if (category)
            card.emojiCategory = category
        return "INLINE_KEYBOARD_EMOJI:" + card.emojiSegment + ":" + card.emojiCategory
    }

    // 调试用：模拟按一个普通键（键码），返回所有修饰键状态
    function pressDebugKey(code: int, sym: string): string {
        if (!controller.devMode) return "dev mode off"
        // 带键名才会走 socket 直通；不带时退回 ydotool（和真实按键一致）
        controller.handleKey({ k: "char", c: code, l: sym })
        return controller.stateSummary()
    }

    // 调试：绕过卡片直接走 socket 直通，用来单独验证这条通道
    function debugDirectKey(sym: string): string {
        if (!controller.devMode) return "dev mode off"
        const ok = controller.sendFcitx("key:" + sym)
        return "INLINE_KEYBOARD_DIRECT:" + sym + ":sent=" + ok
            + ":engine=" + (!controller.fcitxImKeyboard)
            + ":combo=" + controller.hasComboModifier
    }

    // 调试用：keys / functions 之间切换
    // 临时：走用户的真实路径（点动作 → handleQuick → beginResize）
    function debugVoiceMic(): string {
        if (!controller.devMode) return "dev mode off"
        controller.voiceMicPressed()
        return "voice=" + (controller.voiceActive ? "rec" : "idle")
            + "/" + (controller.voiceMinimal ? "mini" : "full")
    }

    // 调试：写一个设置项。走 PluginService.savePluginData（和设置页同一条路），
    // 写完 daemon 的 onPluginDataChanged → reloadSettings 立刻生效，不用重启。
    // value 用字符串传，这里按 true/false/整数解析，其余当字符串。
    function debugSetSetting(key: string, value: string): string {
        if (!controller.devMode)
            return "dev mode off"
        if (!key)
            return "no-key"
        let parsed = value
        if (value === "true")
            parsed = true
        else if (value === "false")
            parsed = false
        else if (/^-?\d+$/.test(value))
            parsed = parseInt(value)
        PluginService.savePluginData(controller.pluginId, key, parsed)
        return "SET:" + key + "=" + JSON.stringify(parsed)
    }

    // 调试：直接切语音模式（等价于点语音行左侧按钮）
    function debugVoiceMinimal(on: bool): string {
        if (!controller.devMode) return "dev mode off"
        if (controller.voiceMinimal !== on)
            controller.toggleVoiceMinimal()
        return "minimal=" + controller.voiceMinimal + " floating=" + controller.floating
    }

    function debugMinimize(): string {
        if (!controller.devMode) return "dev mode off"
        controller.toggleMinimize()
        return "min=" + (controller.minimized ? 1 : 0) + " open=" + controller.open
    }

    function debugQuickAction(id: string): string {
        if (!controller.devMode) return "dev mode off"
        controller.handleQuick(id)
        const card = controller.activeCard
        return "mode=" + (card ? card.mode : "-")
            + " page=" + (card ? card.page : "-")
            + " listOpen=" + (card ? card.candListOpen : "-")
    }

    // 调试用：模拟「把列表第 index 个动作拖到卡片坐标 (x,y)」，
    // 用来在没有人手的情况下检查拖动预览（幽灵块 / 让位 / 挤出）
    function debugDrag(index: int, x: int, y: int): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "INLINE_KEYBOARD_NO_CARD"
        const list = card.availableActions || []
        if (index < 0 || index >= list.length)
            return "INLINE_KEYBOARD_BAD_INDEX"
        card.dragOwner = "cell:" + index
        card.dragFrom = ""
        card.dragIndex = index
        card.dragFromIndex = -1
        card.dragActive = true
        card.ghostAction = list[index]
        card.ghostX = x
        card.ghostY = y
        card.updateTargetFromGhost()
        card.updateDropTargets()
        return "INLINE_KEYBOARD_DRAG:" + list[index].id
               + ":barIndex=" + card.dragBarIndex
               + ":listIndex=" + card.dragTarget
    }

    // dms ipc call inlineKeyboard debugCand "一,二,三" 注入假候选；空串清除
    // 参数必须标类型：不标会被推断成 QVariant，DMS 的 IPC
    function debugCand(csv: string): string {
        if (!controller.devMode) return "dev mode off"
        const text = String(csv || "")
        controller.debugCandItems = text === ""
            ? [] : text.split(",").map(s => s.trim()).filter(s => s !== "")
        return controller.debugCandItems.length + " 项"
    }

    // dms ipc call inlineKeyboard debugCandList   切换候选列表页
    function debugCandList(): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "no-card"
        const before = card.candListOpen
        card.toggleCandList()
        const after = card.candListOpen
        return "before=" + before + " after=" + after
            + " model=" + card.candListModel.length
            + " bar=" + card.candBarItems.length
            + " n=" + card.candBarCount
            + " list=" + card.candListItems.length
            + " barFirst=" + (card.candBarItems.length > 0
                              ? card.candBarItems[0].t : "-")
            + " listFirst=" + (card.candListItems.length > 0
                               ? card.candListItems[0].t : "-")
    }

    // 临时：验证候选列表页右侧按钮（滚动 / 退格 / 回车）
    function debugSideButton(act: string): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "no-card"
        const panel = card.candListPanel
        if (!panel)
            return "no-panel"
        if (act === "up" || act === "down") {
            const before = panel.contentYOf()
            panel.scrollBy(act === "up" ? -1 : 1)
            return "act=" + act + " y=" + Math.round(before)
                + " -> " + Math.round(panel.contentYOf())
        }
        if (act === "backspace") {
            card.keyPressed({ k: "key", l: "Backspace", c: 14 })
            return "act=backspace sent"
        }
        if (act === "enter") {
            card.keyPressed({ k: "key", l: "Enter", c: 28 })
            return "act=enter sent"
        }
        return "unknown:" + act
    }

    function debugPanel(): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "no-card"
        const panel = card.candListPanel
        if (!panel)
            return "no-panel open=" + card.candListOpen
        return "open=" + card.candListOpen
            + " slice=" + card.candListSlice.length
            + " items=" + panel.items.length
            + " contentH=" + Math.round(panel.contentH)
            + " w=" + Math.round(panel.width)
            + " listW=" + Math.round(panel.listW)
            + " active=" + panel.active
            + " contentY=" + Math.round(panel.contentYOf())
    }

    function debugRows(): string {
        if (!controller.devMode) return "dev mode off"
        let out = ["im=" + controller.fcitxImName,
                   "ascii=" + controller.imAsciiMode,
                   "list=" + controller.imList.length,
                   "rows=" + controller.imRows.length]
        for (let i = 0; i < controller.imRows.length; i++) {
            const r = controller.imRows[i]
            out.push("  [" + i + "] " + r.name
                + " ascii=" + r.ascii
                + " kb=" + r.keyboard
                + " cur=" + r.current
                + " label=" + r.label
                + " text=" + r.text)
        }
        return out.join("\n")
    }

    function debugCycleIm(): string {
        if (!controller.devMode) return "dev mode off"
        controller.cycleIm()
        return "im=" + controller.fcitxImName
            + " rows=" + controller.imRows.length
            + " list=" + controller.imList.length
    }

    // 调试用：直接走 handleQuick 执行一次动作（验证自定义动作的命令链路）
    // 调试：直接把一次按键交给 handleKey（模拟点键盘）
    function debugKey(kind: string, to: string): string {
        if (!controller.devMode) return "dev mode off"
        controller.handleKey({ k: kind, to: to })
        return "INLINE_KEYBOARD_KEY:" + kind + ":to=" + to + ":page=" + controller.page
    }

    // 测试用：只记录将要注入的按键，不真的发到系统（不调 ydotool、不发 socket）
    function debugSetDryRun(on: bool): string {
        if (!controller.devMode)
            return "dev mode off"
        if (typeof keyRouter === "undefined" || !keyRouter)
            return "no-keyrouter"
        keyRouter.dryRun = on
        if (!on)
            keyRouter.dryRunLog = []
        // 回读确认真的设上了：设不上就等于没有拦截，脚本必须能发现
        return "INLINE_KEYBOARD_DRY_RUN:" + (on ? "on" : "off")
            + ":now=" + (keyRouter.dryRun ? "on" : "off")
    }

    // 读回干跑期间记下的注入项：sym/kind/route/code/mods
    function debugInjected(): string {
        if (!controller.devMode)
            return "dev mode off"
        if (typeof keyRouter === "undefined" || !keyRouter)
            return "no-keyrouter"
        const log = keyRouter.dryRunLog || []
        const out = []
        for (let i = 0; i < log.length; i++) {
            const e = log[i]
            // tab 分隔：sym 本身可能是 / 或空格（/ 键、Caps Lock）
            out.push([e.sym, e.kind, e.route, e.code, "m" + e.mods].join("\t"))
        }
        // 一条一行：标签里可能有空格（Caps Lock），不能用空格分隔
        return "INJECTED[" + log.length + "]:\n" + out.join("\n")
    }

    function debugClearInjected(): string {
        if (!controller.devMode) return "dev mode off"
        keyRouter.dryRunLog = []
        return "INLINE_KEYBOARD_INJECTED_CLEARED"
    }









    // 调试：当前页键表（下标|标签|键码|类型|Fn标签|有上档）。
    // 验收脚本按下标逐键点击，期望值另从 layouts/phone.js 算。
    function debugKeyList(): string {
        if (!controller.devMode)
            return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "no-card"
        return card.keySnapshot().map(k => [k.index, k.label, k.code, k.kind,
                                            k.fnLabel, k.hasShift ? 1 : 0].join("|")).join("\n")
    }

    // 模拟一次点击 / 长按：target 决定点哪个控件，a / b 是各自的参数。
    // 全部走控件自己的 tapAt()，和手指是同一条路径。
    function debugTap(target: string, a: string, b: int): string {
        if (!controller.devMode)
            return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "no-card"
        switch (target) {
        case "key":
            if (!card.pointerTap(a, b))
                return "not-found:" + a
            return "INLINE_KEYBOARD_TAP:" + a + ":" + b
        case "keyAt":
            if (!card.pointerTapAt(parseInt(a), b))
                return "not-found:index:" + a
            return "INLINE_KEYBOARD_TAP:index:" + a + ":" + b
        case "expand":
            return card.pointerTapExpand() ? "INLINE_KEYBOARD_TAP:candExpand" : "not-found:candExpand"
        case "side":
            return card.pointerTapSide(a) ? "INLINE_KEYBOARD_TAP:candSide:" + a : "not-found:" + a
        case "bottom":
            return card.pointerTapBottom(a) ? "INLINE_KEYBOARD_TAP:bottom:" + a : "not-found:" + a
        case "nav":
            return card.pointerTapNav() ? "INLINE_KEYBOARD_TAP:nav" : "not-found:nav"
        case "action":
            return card.pointerTapAction(a) ? "INLINE_KEYBOARD_TAP:action:" + a : "not-found:" + a
        case "bar":
            return card.pointerTapBarAction(a) ? "INLINE_KEYBOARD_TAP:bar:" + a : "not-found:" + a
        case "slot":
            return card.pointerTapSlot() ? "INLINE_KEYBOARD_TAP:slot" : "not-found:slot"
        case "emojiCat":
            return card.pointerTapEmojiCat(a) ? "INLINE_KEYBOARD_TAP:emojiCat:" + a : "not-found:" + a
        }
        return "unknown-target:" + target
    }

    // ---- 几何 / 外观：读 ----
    // 位置取卡片自己在屏幕上的左上角，停靠和浮动同一套算法；
    // 尺寸读实际值，另给一份落盘值（savedW/H）方便对比是否已经生效。
    function debugGeometry(): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card) return "no-card"
        const p = card.mapToItem(null, 0, 0)
        const win = controller.floating ? controller.floatingLoaderItem : controller.dockedLoaderItem
        const pos = (win && win.posX !== undefined)
            ? Math.round(win.posX) + "," + Math.round(win.posY) : "-"
        return "GEO:x=" + Math.round(p.x) + " y=" + Math.round(p.y)
            + " w=" + Math.round(card.width) + " h=" + Math.round(card.height)
            + " bg=" + Math.round(controller.bgOpacity * 100)
            + " key=" + Math.round(controller.keyOpacity * 100)
            + " float=" + (controller.floating ? 1 : 0)
            + " dockFill=" + (controller.dockFill ? 1 : 0)
            + " saved=" + Math.round(controller.savedW) + "x" + Math.round(controller.savedH)
            + " screen=" + Math.round(card.screenW) + "x" + Math.round(card.screenH)
            + " pos=" + pos
    }

    // ---- 几何 / 外观：写 ----
    // 尺寸走和拖拽松手同一条路：normalizeSize 夹进上下限，再 persistSize 落盘。
    function debugSetSize(w: int, h: int): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card) return "no-card"
        const norm = Resize.normalizeSize(
            { w: w, h: h },
            controller.baseKbWidth, controller.baseKbHeight,
            card.screenW, Math.round(card.screenH * 2 / 3), 1)
        controller.persistSize(norm.w, norm.h)
        return "SIZE:" + norm.w + "x" + norm.h
    }

    // 透明度：0–100 的百分比，写进同名设置并立刻生效
    function debugSetOpacity(bg: int, key: int): string {
        if (!controller.devMode) return "dev mode off"
        const b = Math.max(0, Math.min(100, bg))
        const k = Math.max(0, Math.min(100, key))
        controller.bgOpacity = b / 100.0
        controller.keyOpacity = k / 100.0
        PluginService.savePluginData(controller.pluginId, "bgOpacity", b)
        PluginService.savePluginData(controller.pluginId, "keyOpacity", k)
        return "OPACITY:" + b + "/" + k
    }

    // 位置：只有浮动模式能设（停靠位置由布局决定），夹进屏幕后落盘
    function debugSetPosition(x: int, y: int): string {
        if (!controller.devMode) return "dev mode off"
        if (!controller.floating) return "docked:no-position"
        const win = controller.floatingLoaderItem
        const card = controller.activeCard
        if (!win || !card) return "no-window"
        const maxX = Math.max(0, Math.round(card.screenW - card.width))
        const maxY = Math.max(0, Math.round(card.screenH - card.height))
        const px = Math.max(0, Math.min(maxX, x))
        const py = Math.max(0, Math.min(maxY, y))
        win.posX = px
        win.posY = py
        controller.saveFloatPosition(px, py)
        return "POS:" + px + "," + py
    }


    // 调试：直接注入一个键码（不经过卡片，方便无触摸屏验证输入后端）
    function debugType(code: string): string {
        if (!controller.devMode) return "dev mode off"
        controller.injectKey(Number(code))
        return "INLINE_KEYBOARD_TYPE:" + code + ":ydotoold=" + (controller.ydotooldUp ? "up" : "down")
    }

    // 调试用：生成 count 个占位动作（测滚动、容量、拖放用）。
    // 同时清空固定栏和槽，避免它们指向已经不存在的 id。
    function debugSetActions(count: int): string {
        if (!controller.devMode) return "dev mode off"
        const icons = ["label", "star", "circle", "square", "flag",
                       "bookmark", "bolt", "eco", "face", "cake"]
        const list = []
        for (let i = 0; i < count; i++) {
            list.push({
                id: "p" + (i + 1),
                label: "Placeholder " + (i + 1),
                icon: icons[i % icons.length]
            })
        }
        controller.actions = list
        controller.saveOrder(list)
        controller.quickBarActions = []
        controller.saveQuickBar([])
        controller.slotActionId = ""
        controller.saveSlot("")
        return "INLINE_KEYBOARD_ACTIONS:" + list.length
    }

    // 调试用：模拟「从固定栏第 index 个动作拖到卡片坐标 (x,y)」
    function debugDragFromBar(index: int, x: int, y: int): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "INLINE_KEYBOARD_NO_CARD"
        const bar = card.quickBarActions || []
        if (index < 0 || index >= bar.length)
            return "INLINE_KEYBOARD_BAD_INDEX:" + bar.length
        card.dragOwner = "bar:" + index
        card.dragFrom = "bar"
        card.dragFromIndex = index
        card.dragIndex = -1
        card.dragActive = true
        card.ghostAction = bar[index]
        card.ghostX = x
        card.ghostY = y
        card.updateTargetFromGhost()
        card.updateDropTargets()
        return "INLINE_KEYBOARD_DRAG_FROM_BAR:" + bar[index].id
               + ":barIndex=" + card.dragBarIndex
               + ":listIndex=" + card.dragTarget
    }

    // 调试用：结束上面模拟的拖动（走真实落盘路径）
    function debugDrop(): string {
        if (!controller.devMode) return "dev mode off"
        const card = controller.activeCard
        if (!card)
            return "INLINE_KEYBOARD_NO_CARD"
        card.endDrag()
        return "INLINE_KEYBOARD_DROPPED"
    }
}
