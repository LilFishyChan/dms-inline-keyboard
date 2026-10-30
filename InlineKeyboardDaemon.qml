// Inline Keyboard 的守护插件：唯一持有持久状态的地方。
// 职责：读写插件设置与运行状态、提供 IPC 命令、按需创建/销毁两个键盘窗口、
// 向卡片下发动作表与设置。fcitx5 通信在 FcitxBridge、按键路由在 KeyRouter。
// 卡片和窗口不直接读配置文件，全部通过这里的属性和信号。

import QtQuick
import "data.js" as Data
import "layouts/special-keys.js" as SpecialKeys
import "layouts/resize.js" as Resize
import "actions.js" as Actions
import "modifiers.js" as Modifiers
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Plugins

// 键盘 daemon：持有键盘状态，按需创建贴底 / 浮动窗口。
// 当前阶段只做布局与状态切换；按键注入和候选栏数据后续接。
PluginComponent {
    id: root

    // fcitx5 通信全部在这个桥里（socket 推送、状态解析、候选、输入法清单）
    FcitxBridge {
        id: fcitxBridge
        keyboardOpen: root.open
    }

    // 按键路由（修饰键状态机 + 直通/ydotool 选择）
    KeyRouter {
        id: keyRouter
        bridge: fcitxBridge
        active: root.keyboardVisible
        actions: root.actions
        modifierMode: root.modifierMode
    }

    // ---- 状态（窗口销毁后仍保留）----
    property bool open: PluginService.getGlobalVar(root.pluginId, "open", false)
    property bool floating: PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
    property bool avoidWindows: PluginService.loadPluginData(root.pluginId, "avoidWindows", true)
    readonly property bool fnActive: root.fnState > 0

    // 调试 IPC（debug* 系列）默认关闭：其中 debugAddCommandAction 能把任意 sh -c
    // 存成持久动作、debugRunAction 会执行它，不能对任何本地进程开放。
    // 需要时用 `INLINE_KEYBOARD_DEV=1 systemctl --user restart dms` 打开。
    readonly property bool devMode: Quickshell.env("INLINE_KEYBOARD_DEV") === "1"
    // 键位页 id：page1 主键区 / page2 F 区 / emoji 表情 & 符号页
    // （卡片的 page 属性是绑定到这里的，任何地方都别直接给卡片赋值，否则绑定断掉）
    property string page: "page1"
    readonly property var knownPages: ["page1", "page2", "emoji"]
    // 换页的唯一入口：非法的目标页直接忽略，避免卡在一个没有布局的页上
    function setPage(p) {
        if (root.knownPages.indexOf(p) < 0) {
            console.warn("inlineKeyboard: 未知键位页 " + p)
            return root.page
        }
        root.page = p
        return root.page
    }
    // keys = 正常键盘 / functions = 快捷功能列表（顶部四格按钮切换）
    property string mode: "keys"
    // 动作列表编辑态
    property bool editing: false

    // ---- 修饰键状态（实际存在 KeyRouter 里，这里 alias 给卡片和设置页用）----
    // 0 = 未激活 / 1 = 一次性（下一个普通键后复位）/ 2 = 锁定
    property alias shiftState: keyRouter.shiftState
    property alias capsState: keyRouter.capsState
    property alias ctrlState: keyRouter.ctrlState
    property alias altState: keyRouter.altState
    property alias superState: keyRouter.superState
    property alias fnState: keyRouter.fnState
    property alias modifierStates: keyRouter.modifierStates
    property alias hasComboModifier: keyRouter.hasComboModifier
    property alias ydotooldUp: keyRouter.ydotooldUp

    // 切换方式：noLock / toggle / tapLock / doubleTapLock（设置页可选）
    property string modifierMode: PluginService.loadPluginData(root.pluginId, "modifierMode", "doubleTapLock")
    // 长按自动重复的间隔（毫秒）
    property int repeatInterval: PluginService.loadPluginData(root.pluginId, "repeatInterval", 60)

    // ---- fcitx5 状态（实际存在 FcitxBridge 里，这里 alias 给卡片和窗口用）----
    readonly property alias fcitxCandidates: fcitxBridge.candidates
    readonly property alias fcitxPreedit: fcitxBridge.preedit

    // addon 推回来的 label 已经是目标值了 → 立刻收起乐观态，
    // 这样正常情况下切换是「瞬间到位」，不会白压 1 秒
    onFcitxImLabelChanged: {
        // 只关「乐观显示」，**不清 optimisticImIdx**：
        // 那个索引是「上次点到行几」的账本，清掉后下次点击又会从
        // 真实值重算，连续点击就会一直在同一项上打转。
        if (root.optimisticImActive && root.optimisticImLabel === fcitxBridge.imLabel)
            root.optimisticImActive = false
    }
    readonly property alias fcitxVisible: fcitxBridge.panelVisible
    readonly property alias fcitxImKeyboard: fcitxBridge.imKeyboard
    readonly property alias fcitxImName: fcitxBridge.imName
    // 切换输入法时的乐观显示：点下地球键的那一刻就把图标/标签换成目标值，
    // 不等 addon 回推。否则从 en 切到万象会先闪一下 abc 再变「万」——
    // D-Bus 切输入法是异步的，中间那几百毫秒就在显示旧状态。
    property string optimisticImLabel: ""
    property string optimisticImIcon: ""
    property bool optimisticImActive: false

    // 乐观值最多压 1 秒。超时还没等到新状态就回落到真实值，
    // 免得切换失败时图标永远停在目标输入法上。
    Timer {
        id: optimisticImTimer
        interval: 1000
        // 超时同理：只回落到真实值，不清索引
        onTriggered: root.optimisticImActive = false
    }

    readonly property string fcitxImLabel: root.optimisticImActive
        ? root.optimisticImLabel : fcitxBridge.imLabel
    readonly property string fcitxImIcon: root.optimisticImActive
        ? root.optimisticImIcon : fcitxBridge.imIcon
    readonly property alias fcitxHasPrev: fcitxBridge.hasPrev
    readonly property alias fcitxHasMore: fcitxBridge.hasMore
    readonly property alias fcitxSocketUp: fcitxBridge.socketUp
    readonly property alias fcitxLastError: fcitxBridge.lastError
    readonly property alias imList: fcitxBridge.imList
    // 不能写 alias：imRows 是 property var 存数组，alias 只跟住引用，
    // bridge 重建数组后这里不会重新求值，nextImRow 就一直读到没有 current 的旧数组。
    readonly property var imRows: fcitxBridge.imRows
    readonly property alias imAsciiMode: fcitxBridge.isAsciiMode

    // 键盘内始终显示预编辑（不因应用自己渲染了 preedit 就隐藏）
    property bool alwaysShowPreedit: PluginService.loadPluginData(root.pluginId, "alwaysShowPreedit", false)

    // 预编辑是否由应用自己画（fcitx5 的 clientPreedit 非空）。
    // 应用自己把拼音串画进输入框时（embedded），键盘就不再重复显示。
    // alwaysShowPreedit 打开则无视这个判断，键盘内始终画一行。
    readonly property bool fcitxPreeditEmbedded: !root.alwaysShowPreedit && fcitxBridge.preeditEmbedded
    // 全量候选（候选列表页用）
    readonly property var allCandidates: fcitxBridge.allCandidates
    readonly property int candRevision: fcitxBridge.candRevision

    // 调试候选：终端这类不支持 text-input 的窗口里 fcitx5 不产生候选，
    // 靠它把候选栏调出来看布局。真实候选非空时仍然以真实值为准。
    property var debugCandItems: []

    // 转发给 FcitxBridge 的解析入口（statusRead 兜底和 debug 用）
    function applyFcitxStatus(raw) { fcitxBridge.applyStatus(raw) }
    function applyImList(raw) { fcitxBridge.applyImList(raw) }

    // ---- 按键注入 / 修饰键：全部在 KeyRouter 里，这里转发 ----
    function injectKey(code, sym) { keyRouter.injectKey(code, sym) }
    // 换页键（k = "page"）改的是键盘自身的状态，状态在 daemon 上，所以在这里拦下；
    // 其余键交给 KeyRouter 决定「直通 fcitx5 / ydotool」。
    // 拆组件时这个分支漏掉过一次：page 键没有键码，走到 injectKey 直接 return，点击静默无效。
    function handleKey(keyData) {
        if (!keyData)
            return
        if (keyData.k === "page") {
            root.setPage(keyData.to)
            return
        }
        keyRouter.handleKey(keyData)
    }
    function modifierStateOf(name) { return keyRouter.stateOf(name) }
    function setModifierState(name, v) { keyRouter.setState(name, v) }
    function cycleModifier(name) { keyRouter.cycleModifier(name) }
    function clearModifierStates() { keyRouter.clearAllModifiers() }
    function modifierPress(kd) { keyRouter.modifierPress(kd) }
    function modifierRelease(kd) { keyRouter.modifierRelease(kd) }
    function clearTransientModifiers() { keyRouter.clearTransientModifiers() }
    function probeYdotoold() { keyRouter.probeYdotoold() }
    function sendFcitx(line) { return fcitxBridge.sendFcitx(line) }

    // ---- 表情 / 符号上屏 ----
    // 优先级：addon 进程内 commit（直接进输入框，用户不用再操作）
    //        > 复制到剪贴板（没有 fcitx5 扩展时唯一可行的一条）。
    property string lastTextCommit: ""
    property string lastTextCommitVia: ""
    // 提示节流：同一条消息 3 秒内只弹一次
    property double lastTextToastAt: 0
    function typeText(text) {
        if (!text)
            return ""
        lastTextCommit = text
        if (fcitxBridge.commitText(text)) {
            lastTextCommitVia = "commit"
            return "commit"
        }
        fcitxBridge.copyText(text)
        const copied = fcitxBridge.clipboardAvailable
        lastTextCommitVia = copied ? "clipboard" : "none"
        // 连点几个表情时别刷一屏提示：同一条消息 3 秒内只弹一次
        const now = Date.now()
        if (typeof ToastService !== "undefined" && ToastService
                && now - root.lastTextToastAt > 3000) {
            root.lastTextToastAt = now
            // 「什么都没成功」要说清楚缺什么、怎么补 ——
            // 只说「失败了」，用户完全不知道该装什么（平板上就是这样）
            const term = copied
                ? "Copied — long press the text field to paste"
                : "Cannot insert text: install the fcitx5 addon (inline-keyboard-status)"
            ToastService.showInfo((typeof I18n !== "undefined" && I18n && I18n.trFor)
                                  ? I18n.trFor(root.pluginId, term) : term)
        }
        return lastTextCommitVia
    }

    // ---- 错误捕获 ----
    // QML 里函数抛异常时，IPC 调用方拿到的是空字符串，分不清「没返回」
    // 和「抛了」——排查时极浪费时间（actionById 不存在那次就是）。
    // 所有对外入口都过 safeCall，异常变成可读的 ERR:... 字符串。
    property string lastError: ""

    function safeCall(name, fn) {
        try {
            return fn()
        } catch (e) {
            const msg = "ERR:" + name + ": " + e
            root.lastError = msg
            console.error("[inlineKeyboard] " + msg)
            return msg
        }
    }

    // ---- 动作命令执行 ----
    // 所有动作共用一条 Process，忙时排队一条。
    // 直接改 running 中的 command 会被 Qt 丢掉，用户看到的就是「点了没反应」。
    property var pendingCommand: null

    Process {
        id: quickProc
        command: ["true"]
    }

    function runCommand(cmd) {
        if (quickProc.running) {
            root.pendingCommand = cmd
            return
        }
        quickProc.command = cmd
        quickProc.running = true
    }

    Process {
        id: pendingDrain
        command: ["true"]
    }

    Connections {
        target: quickProc
        function onRunningChanged() {
            if (quickProc.running || !root.pendingCommand)
                return
            const next = root.pendingCommand
            root.pendingCommand = null
            root.runCommand(next)
        }
    }

    function notifyUnimplemented(label) { keyRouter.notifyUnimplemented(label) }
    function findAction(key) { return keyRouter.findAction(key) }

    // 按 id 找动作（自定义动作要拿它的 cmd）
    function actionById(id) {
        const list = Actions.toArray(root.actions)
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].id === id)
                return list[i]
        }
        return null
    }

    // 快捷动作分发：内置动作先判，剩下的当自定义动作按 cmd 跑
    // 进透明度面板：记下当前值（「取消」用它还原），然后切模式。
    // 固定栏走 handleQuick，列表页走 modeChangeRequested，两条路都要这份快照。
    function enterTransparency() {
        root.prevBgOpacity = root.bgOpacity
        root.prevKeyOpacity = root.keyOpacity
        root.mode = "transparency"
    }

    // 内置动作的处理函数表：id → 要执行的插件内部逻辑。
    // 新增内置动作只需要在 actions.js 里加一条（带 kind: "builtin"）再加上这里的函数，
    // 不用再动 UI —— 三个入口都只发 id，执行永远走 handleQuick 这一条路。
    readonly property var builtinHandlers: ({
        "close": function() { root.hideKeyboard() },
        "float": function() { root.toggleFloating() },
        "settings": function() {
            root.runCommand(["dms", "ipc", "call", "settings", "openWith", "plugin:inlineKeyboard"])
        },
        "nextIm": function() { root.cycleIm() },
        "clipboard": function() {
            root.runCommand(["dms", "ipc", "call", "clipboard", "toggle"])
        },
        "mic": function() {
            // 语音行占的是顶部那一行，先回主页面才看得到
            root.mode = "keys"
            root.toggleVoice()
        },
        "minimize": function() { root.toggleMinimize() },
        "size": function() { root.beginResize() },
        "opacity": function() { root.enterTransparency() },
        "avoid": function() {
            root.avoidWindows = !root.avoidWindows
            PluginService.savePluginData(root.pluginId, "avoidWindows", root.avoidWindows)
        },
        "undo": function() {
            root.runCommand(["ydotool", "key", "29:1", "44:1", "44:0", "29:0"])
        },
        "redo": function() {
            root.runCommand(["ydotool", "key", "29:1", "42:1", "44:1", "44:0", "42:0", "29:0"])
        }
    })

    /**
     * 动作的唯一执行入口。动作列表、顶部固定栏、右上角固定框都只发 id 到这里。
     *
     * 怎么执行完全由动作数据决定（kind）：
     *   kind === "cmd"      → 跑动作自己的 cmd
     *   kind === "builtin"  → 查 builtinHandlers
     * 不按 id 写 switch，新增动作不用改这里。
     */
    function handleQuick(action) {
        const def = root.actionById(action)
        // kind === "cmd" 的动作跑自己的命令；这类动作必然在动作表里
        if (def && def.kind === "cmd") {
            if (def.cmd && def.cmd.trim() !== "")
                root.runCommand(["sh", "-c", def.cmd])
            else
                console.error("[Inline Keyboard] cmd 类动作缺少命令:", action)
            return
        }
        // 内置逻辑不要求动作表里有这一项：右上角 ✕、空白区的 Enter 这类
        // 固定按钮不在动作表里，但同样走这一条路
        const handler = root.builtinHandlers[action]
        if (handler) {
            handler()
            return
        }
        // 动作表里有 cmd 但 kind 没标对的老配置，兜底按命令跑
        if (def && def.cmd && def.cmd.trim() !== "") {
            root.runCommand(["sh", "-c", def.cmd])
            return
        }
        console.error("[Inline Keyboard] 动作没有处理函数:", action)
    }

    // ---- 尺寸设置（设置页可调）----
    // 动作表：kind=builtin 走内部逻辑；dms / compositor / cmd 都执行 cmd 里的完整命令。
    // label 存英文源串，显示时由卡片过一遍 tr()（用户自定义动作的名字原样返回）
    // 内置动作表在 actions.js 里（设置页也用同一份）
    readonly property var defaultActions: Actions.defaultActions()

    // 用户可配置的动作表（存设置里）
    // 顶部快捷栏中间那组动作
    property var quickBarActions: PluginService.loadPluginData(root.pluginId, "quickBarActions", [])

    // 右上角槽里的动作 id
    property string slotActionId: PluginService.loadPluginData(root.pluginId, "slotActionId", "float")

    property var actions: {
        const v = PluginService.loadPluginData(root.pluginId, "actions", null)
        if (!v || !v.length)
            return root.defaultActions
        // 插件升级后新增的内置动作不会自动出现在老配置里，
        // 这里补到末尾（hidden: true，不挤进功能页），
        // 否则「设置页看不到、动作表也调不到」
        return Actions.mergeNewBuiltins(root.sanitizeActions(v), root.defaultActions)
    }

    // 按 id 去重（避免拖动过程中重复写入）
    // 清洗外部配置（去重/去无效项）；实现与单测在 actions.js
    function sanitizeActions(list) {
        return Actions.sanitizeActions(list, root.defaultActions)
    }

    // 外观：缩放 + 透明度，都从设置读（PluginSettings 存的是百分数）
    property real bgOpacity: PluginService.loadPluginData(root.pluginId, "bgOpacity", 100) / 100.0
    property real keyOpacity: PluginService.loadPluginData(root.pluginId, "keyOpacity", 100) / 100.0
    onBgOpacityChanged: opacitySaveTimer.restart()
    onKeyOpacityChanged: opacitySaveTimer.restart()

    // 拖滑块时值每帧都变，停手 400ms 再写盘
    Timer {
        id: opacitySaveTimer
        interval: 400
        onTriggered: {
            // 先取到局部值：第一次 save 会触发 pluginDataChanged → reloadSettings
            // 把另一个属性覆盖回去，第二次 save 再读 root 就是旧值了。
            const bg = Math.round(root.bgOpacity * 100)
            const key = Math.round(root.keyOpacity * 100)
            PluginService.savePluginData(root.pluginId, "bgOpacity", bg)
            PluginService.savePluginData(root.pluginId, "keyOpacity", key)
        }
    }
    // 进入透明度面板时的快照，取消要还原。
    // ActionList 里点击动作时总会写这两个属性，缺了就是 ReferenceError ——
    // 表现成「点透明度没反应」，很容易误判成面板本身坏了。
    // vinput 是**可选**扩展：没装的时候语音动作显示为禁用，
    // 键盘其它功能完全不受影响。探测一次即可（不装/装了不会在运行中变）。
    property bool voiceAvailable: false

    Process {
        id: vinputProbe
        running: true
        command: ["sh", "-c", "command -v vinput >/dev/null && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: root.voiceAvailable = String(text || "").trim() === "yes"
        }
    }

    // 语音输入（fcitx5-vinput）。vinput 没有「正在录音吗」的查询接口
    // （只有 daemon status，那是服务本身的状态），所以这里记一份乐观状态：
    // 点一次开始、再点一次停止，键盘关闭时兜底停掉。
    property bool voiceActive: false

    // 动作列表 / 固定槽里的麦克风：开始或结束语音输入。
    // 这是唯一的「开始」入口 —— 语音行里的按钮只负责结束或暂停。
    function toggleVoice() {
        if (!root.voiceAvailable)
            return
        if (root.voiceActive) {
            root.stopVoice()
            return
        }
        root.voiceActive = true
        root.runCommand(["vinput", "recording", "start"])
    }

    // 语音行右侧的麦克风：按当前显示方式分流
    //   普通模式（全键盘）  → 结束语音输入，语音行一起退掉
    //   语音模式（只剩语音行）→ 暂停 / 继续，语音行留着
    function voiceMicPressed() {
        if (!root.voiceAvailable)
            return
        if (root.voiceMinimal) {
            // 语音模式下是「暂停 / 继续」：状态要跟着翻，
            // 否则麦克风的激活态（图标色 + 描边）不会变
            root.voiceActive = !root.voiceActive
            root.runCommand(["vinput", "recording", "toggle"])
            return
        }
        root.stopVoice()
    }

    // 最小化：整个键盘收成屏幕角上一个浮动的小按钮
    property bool minimized: false
    // 小圆按钮的位置（距右/下边缘的像素；-1 = 还没拖过，由窗口用默认边距）
    property real miniPosRight: PluginService.loadPluginData(root.pluginId, "miniPosRight", -1)
    property real miniPosBottom: PluginService.loadPluginData(root.pluginId, "miniPosBottom", -1)
    // 浮动键盘的位置（-1 = 还没拖过，由窗口按默认位置摆）
    property real floatPosX: PluginService.loadPluginData(root.pluginId, "floatPosX", -1)
    property real floatPosY: PluginService.loadPluginData(root.pluginId, "floatPosY", -1)

    /** 浮动键盘拖完落盘：下次浮动打开回到同一位置。 */
    function saveFloatPosition(x, y) {
        // 先取局部值再存：第一次 save 会触发 pluginDataChanged → reloadSettings，
        // 第二次读到的东西可能已经被改过了
        const px = Math.round(x)
        const py = Math.round(y)
        root.floatPosX = px
        root.floatPosY = py
        root.lastSelfSaveAt = Date.now()
        PluginService.savePluginData(root.pluginId, "floatPosX", px)
        PluginService.savePluginData(root.pluginId, "floatPosY", py)
    }

    /** 小圆按钮拖完落盘：下次最小化回到同一个地方。 */
    function saveMiniPos(right, bottom) {
        root.miniPosRight = right
        root.miniPosBottom = bottom
        root.lastSelfSaveAt = Date.now()
        PluginService.savePluginData(root.pluginId, "miniPosRight", right)
        PluginService.savePluginData(root.pluginId, "miniPosBottom", bottom)
    }

    // 语音模式：切浮动 + 只显示顶部语音行
    property bool voiceMinimal: false

    // VoiceBar 的两个按钮统一调 controller.voiceMicRequested() /
    // controller.voiceMinimalRequested()。主键盘里 controller 是卡片（信号），
    // 胶囊里 controller 是 daemon，所以这里补同名方法，让两种宿主都能调。
    function voiceMicRequested() {
        root.voiceMicPressed()
    }

    function voiceMinimalRequested() {
        root.toggleVoiceMinimal()
    }

    function toggleVoiceMinimal() {
        root.voiceMinimal = !root.voiceMinimal
        root.syncVoiceWindows()
    }

    /**
     * 把默认动作表里新增的内置动作写回用户配置。
     *
     * actions 是快照式存储：保存过之后就再也不会跟默认表合并。
     * 只做运行时合并（mergeNewBuiltins）的话 daemon 能调到，但设置页
     * 读的是保存值，用户看不到这些新动作，也就没法把它们拖到功能页。
     * 所以启动时补一次并落盘，判据是「合并后变长了」。
     */
    function migrateBuiltinActions() {
        const saved = PluginService.loadPluginData(root.pluginId, "actions", null)
        if (!saved || !saved.length)
            return                       // 空配置直接用默认表，不需要迁移
        const merged = Actions.mergeNewBuiltins(root.sanitizeActions(saved), root.defaultActions)
        if (merged.length > Actions.toArray(saved).length) {
            PluginService.savePluginData(root.pluginId, "actions", merged)
            root.actions = merged
            console.error("[Inline Keyboard] 动作表补入 " + (merged.length - Actions.toArray(saved).length) + " 个新内置动作")
        }
    }

    /**
     * 老的 Win 键形态 "windows" 已从选项里移除（和 system 是同一个 ⌘ 图标），
     * 归一成 "system" 并落盘。
     *
     * daemon 自己的 winKeyStyle 已经过 normalizeWinLook（windows→system），
     * 但设置页的 SelectionSetting 直接读原始保存值 —— 不清掉这份老值的话，
     * 下拉框会显示 "windows" 这个不在选项里的裸字符串。
     */
    function migrateWinKeyStyle() {
        const raw = PluginService.loadPluginData(root.pluginId, "winKeyStyle", "mod")
        if (raw !== "windows")
            return
        root.lastSelfSaveAt = Date.now()
        PluginService.savePluginData(root.pluginId, "winKeyStyle", "system")
    }

    /**
     * 销毁两个键盘窗口实例（停靠 / 浮动）。
     *
     * 必须销毁而不是 visible = false：layer surface 隐藏后输入区域还留在屏幕上，
     * 会把语音胶囊、最小化按钮这些浮层的点击全吃掉。
     */
    function destroyKeyboards() {
        dockedLoader.active = false
        floatingLoader.active = false
    }

    /**
     * 最小化：键盘整个收起，只留一个浮动的圆按钮。点按钮恢复。
     *
     * 和语音模式一样，主键盘窗口要**销毁**而不是隐藏 —— layer surface 隐藏后
     * 输入区域还在屏幕上，会把小按钮的点击吃掉。
     */
    function minimizeKeyboard() {
        if (root.minimized)
            return
        // 先标记再收语音：stopVoice() 内部会调 syncVoiceWindows()，它看到键盘
        // 窗口已经销毁会 showKeyboard() 重建一整套窗口，紧接着又被下面
        // destroyKeyboards() 拆掉 —— 白建一次、界面上还会闪一下。
        // minimized 先置 true，syncVoiceWindows 就不会再重建。
        root.minimized = true
        root.stopVoice()
        root.destroyKeyboards()
        // 最小化**仍然算键盘开着**（open 保持 true），所以不能走 open=false：
        // 那会连带触发「关闭」语义。但输入法 UI 不该被一个看不见的键盘占着，
        // 这里只让 syncKeyboardFlag 把 flag 撤掉 → addon setShown(false)
        // → classicui 拿回候选窗。onMinimizedChanged 负责触发。
    }

    function restoreFromMinimize() {
        if (!root.minimized)
            return
        root.minimized = false
        // showKeyboard 会把 open 置 true，onMinimizedChanged 重新 touch flag
        root.showKeyboard(false)
    }

    function toggleMinimize() {
        if (root.minimized)
            root.restoreFromMinimize()
        else
            root.minimizeKeyboard()
    }

    /**
     * 语音模式和全键盘是两套窗口，同一时刻只有一套存在。
     *
     * 进语音模式要**销毁**主键盘窗口，不能只 visible=false：layer surface
     * 隐藏后输入区域仍然留在屏幕上，胶囊正好落在它里面，按钮全被吃掉
     * （实测：点了只有主键盘那份 VoiceBar 收到事件）。
     *
     * 注意不能调 hideKeyboard() 来收窗口：它内部有 stopVoice() 兜底，
     * 会把正在进行的录音一起掐掉。
     */
    function syncVoiceWindows() {
        if (root.voiceMinimal) {
            root.destroyKeyboards()
        } else if (!root.keyboardVisible) {
            root.showKeyboard()
        }
    }

    function stopVoice() {
        // 无论是否在录音，都把界面收回全键盘形态
        const wasMinimal = root.voiceMinimal
        root.voiceMinimal = false
        if (wasMinimal)
            root.syncVoiceWindows()
        if (!root.voiceActive)
            return
        root.voiceActive = false
        root.runCommand(["vinput", "recording", "stop"])
    }

    property real prevBgOpacity: 1.0
    property real prevKeyOpacity: 1.0

    // 特殊键（Backspace / Enter / Shift…）的表现：图标 / 缩写 / 完整。
    // 存的是字符串，非法值在读取时归一化，避免设置文件被手改坏后键帽全变空。
    property string specialKeyStyle: SpecialKeys.normalizeStyle(
        PluginService.loadPluginData(root.pluginId, "specialKeyStyle", "full"))

    // Win 键单独的表现：mod（默认，显示「Mod」）/ system / windows
    property string winKeyStyle: SpecialKeys.normalizeWinLook(
        PluginService.loadPluginData(root.pluginId, "winKeyStyle", "mod"))

    // winKeyStyle === "custom" 时使用的图标名
    property string winKeyCustomIcon: PluginService.loadPluginData(
        root.pluginId, "winKeyCustomIcon", "")
    property bool defaultFloating: PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
    // Esc 与 \`~ 键对调（想要 Esc 在左上角的人用）
    property bool escSwap: PluginService.loadPluginData(root.pluginId, "escSwap", false)
    // 键盘名义尺寸（重置和下限都以它为基准）。窗口与卡片都按它推按键尺寸
    readonly property real baseKbWidth: 1050
    readonly property real baseKbHeight: 444

    // 键盘实际尺寸：由「调整大小」拖出来并保存，默认就是名义尺寸。
    // 原来的 scale 设置项已移除 —— 整体缩放和拖拽调大小是同一件事，
    // 留两个概念会让人分不清「拖到 80% 再乘 90%」到底多大。
    property real savedW: PluginService.loadPluginData(
        root.pluginId, "keyboardWidth", baseKbWidth)
    property real savedH: PluginService.loadPluginData(
        root.pluginId, "keyboardHeight", baseKbHeight)

    // 停靠时是否横向铺满屏幕（调整大小面板里可以切）
    property bool dockFill: PluginService.loadPluginData(
        root.pluginId, "dockFillWidth", true)

    function toggleDockFill() {
        root.dockFill = !root.dockFill
        PluginService.savePluginData(root.pluginId, "dockFillWidth", root.dockFill)
    }

    readonly property real kbWidth: root.savedW
    readonly property real kbHeight: root.savedH

    // ---- 调整大小：拖拽中的预览值，确认后写进 savedW/savedH ----
    // 初值必须是**已保存的尺寸**，不能是名义尺寸：键盘可能已被拖成 840×355，
    // 而名义是 1050×444，用名义值会让预览框一进调整态就跳一大截
    property real resizeW: root.savedW
    property real resizeH: root.savedH
    // 进入调整态时的尺寸，取消要用它还原
    property real resizeOrigW: baseKbWidth
    property real resizeOrigH: baseKbHeight

    function persistSize(w, h) {
        root.savedW = w
        root.savedH = h
        PluginService.savePluginData(root.pluginId, "keyboardWidth", w)
        PluginService.savePluginData(root.pluginId, "keyboardHeight", h)
    }

    function beginResize() {
        root.resizeOrigW = root.savedW
        root.resizeOrigH = root.savedH
        if (root.activeCard) {
            root.activeCard.resizeW = root.savedW
            root.activeCard.resizeH = root.savedH
        }
        // 先回到键盘主页：从功能列表或表情页点「调整大小」时，
        // 遮罩底下的必须是主键区，否则用户看到的是表情面板。
        //
        // 必须写 "page1"，不是 "keys"：page 的合法值是 page1/page2/emoji，
        // 卡片的 spaceEntry 判据是 `page !== "page1"` 就返回 null。
        // 写成 "keys" 会让空格上的输入法标识整块消失，而且退出调整态后
        // page 不会自愈，图标一直不回来。
        root.page = "page1"
        if (root.activeCard)
            root.activeCard.candListOpen = false
        root.mode = "resize"
    }

    // 重置 = 回到名义尺寸，并且立刻落盘（和拖拽松手同一套语义）
    function resetResize() {
        const r = Resize.resetSize(root.baseKbWidth, root.baseKbHeight,
                                   root.baseKbWidth * 0.8, root.baseKbHeight * 0.8)
        if (root.resizeCard) {
            root.resizeCard.resizeW = r.w
            root.resizeCard.resizeH = r.h
        }
        root.persistSize(r.w, r.h)
        // 重置后的尺寸成为新的"取消基准"，否则点取消会弹回重置前的值
        root.resizeOrigW = r.w
        root.resizeOrigH = r.h
    }

    // resizeW/H 的**唯一真相在卡片上**（DragHandler 改的是卡片那份）。
    // daemon 里曾经也存了一份，结果拖拽改卡片、commit 读 daemon，
    // 两个值从不同步 —— 松手后尺寸"没变"就是这么来的。
    readonly property var resizeCard: root.activeCard

    function commitResize() {
        if (!root.resizeCard)
            return
        // 拖拽松手：立刻落盘，键盘当场变成新尺寸；不关面板，可以接着拖另一边
        root.persistSize(root.resizeCard.resizeW, root.resizeCard.resizeH)
    }

    // 「确定」只负责关面板（尺寸早在松手时已经落了）
    function closeResize() {
        root.mode = "keys"
    }

    // 「取消」还原进入调整态时的尺寸
    function cancelResize() {
        root.persistSize(root.resizeOrigW, root.resizeOrigH)
        if (root.resizeCard) {
            root.resizeCard.resizeW = root.resizeOrigW
            root.resizeCard.resizeH = root.resizeOrigH
        }
        root.mode = "keys"
    }

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== root.pluginId || varName !== "open")
                return
            const want = PluginService.getGlobalVar(root.pluginId, "open", false)
            if (want && !root.keyboardVisible)
                root.showKeyboard()
            else if (!want && root.keyboardVisible)
                // 最小化状态也要彻底关掉：hideKeyboard 会清掉 minimized，
                // 浮窗跟着消失，而不是留一个恢复按钮在屏幕上
                root.hideKeyboard()
        }
        function onPluginDataChanged(pluginId) {
            if (pluginId !== root.pluginId)
                return
            root.reloadSettings()
        }
    }

    // 设置页改完立刻生效。
    // 本插件自己保存动作 / 槽 / 快捷栏时也会触发这里，所以逐项比较后再赋值：
    // 值没变就不写，避免 Repeater 被无谓重建（拖动刚结束那一下尤其明显）。
    // ---- 展开候选：实际在 FcitxBridge 里（addon 一次取完所有页）----
    function selectCandidateByIndex(index) { fcitxBridge.selectCandidate(index) }

    function reloadSettings() {
        // 透明度面板开着时不回读这两个值：自己刚保存会触发 pluginDataChanged，
        // 回读会把还没写盘的另一个值覆盖掉（保存顺序被打乱）。
        if (root.mode !== "transparency") {
            const nextBgOpacity = PluginService.loadPluginData(root.pluginId, "bgOpacity", 100) / 100.0
            if (nextBgOpacity !== root.bgOpacity)
                root.bgOpacity = nextBgOpacity
            const nextKeyOpacity = PluginService.loadPluginData(root.pluginId, "keyOpacity", 100) / 100.0
            if (nextKeyOpacity !== root.keyOpacity)
                root.keyOpacity = nextKeyOpacity
        }
        const nextAvoid = PluginService.loadPluginData(root.pluginId, "avoidWindows", true)
        if (nextAvoid !== root.avoidWindows)
            root.avoidWindows = nextAvoid
        const nextAlwaysPreedit = PluginService.loadPluginData(root.pluginId, "alwaysShowPreedit", false)
        if (nextAlwaysPreedit !== root.alwaysShowPreedit)
            root.alwaysShowPreedit = nextAlwaysPreedit
        const nextDefaultFloating = PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
        if (nextDefaultFloating !== root.defaultFloating) {
            root.defaultFloating = nextDefaultFloating
            // 键盘没打开时，改默认模式立刻作用到下一次打开
            if (!root.keyboardVisible)
                root.floating = nextDefaultFloating
        }
        // 外观类设置：这些属性都是「构造时读一次」（loadPluginData 不是通知属性），
        // 不在这里显式重读的话，设置页改完键盘一点反应都没有 —— 要重开才生效。
        // 踩过：Win 键选「自定义图标」后键盘还是老样子。
        const nextSpecialKeyStyle = SpecialKeys.normalizeStyle(
            PluginService.loadPluginData(root.pluginId, "specialKeyStyle", "full"))
        if (nextSpecialKeyStyle !== root.specialKeyStyle)
            root.specialKeyStyle = nextSpecialKeyStyle
        const nextWinKeyStyle = SpecialKeys.normalizeWinLook(
            PluginService.loadPluginData(root.pluginId, "winKeyStyle", "mod"))
        if (nextWinKeyStyle !== root.winKeyStyle)
            root.winKeyStyle = nextWinKeyStyle
        const nextWinCustomIcon = PluginService.loadPluginData(
            root.pluginId, "winKeyCustomIcon", "")
        if (nextWinCustomIcon !== root.winKeyCustomIcon)
            root.winKeyCustomIcon = nextWinCustomIcon
        const nextEscSwap = PluginService.loadPluginData(root.pluginId, "escSwap", false)
        if (nextEscSwap !== root.escSwap)
            root.escSwap = nextEscSwap
        const nextRepeat = PluginService.loadPluginData(root.pluginId, "repeatInterval", 60)
        if (nextRepeat !== root.repeatInterval)
            root.repeatInterval = nextRepeat

        root.applyActionSettings()
        const nextModifierMode = PluginService.loadPluginData(root.pluginId, "modifierMode", "doubleTapLock")
        if (nextModifierMode !== root.modifierMode) {
            root.modifierMode = nextModifierMode
            root.clearModifierStates()
        }
    }

    // 读取与动作相关的三项设置（构造时与 reloadSettings 共用）
    function applyActionSettings() {
        // 刚自己写过的东西，先等写盘落定：savePluginData 之后 onPluginDataChanged 可能
        // 先读到旧文件，把内存覆盖回旧值 —— 表现就是「同一个动作既在固定栏又在列表里」
        if (Date.now() - root.lastSelfSaveAt < 600)
            return
        const rawActions = PluginService.loadPluginData(root.pluginId, "actions", null)
        const nextActions = (rawActions && rawActions.length)
            ? root.sanitizeActions(rawActions) : root.defaultActions
        if (JSON.stringify(nextActions) !== JSON.stringify(root.actions))
            root.actions = nextActions
        const nextSlot = PluginService.loadPluginData(root.pluginId, "slotActionId", "float")
        if (nextSlot !== root.slotActionId)
            root.slotActionId = nextSlot
        const nextQuickBar = PluginService.loadPluginData(root.pluginId, "quickBarActions", [])
        if (JSON.stringify(nextQuickBar) !== JSON.stringify(root.quickBarActions))
            root.quickBarActions = nextQuickBar
    }

    readonly property bool keyboardVisible:
        // 语音模式下主键盘窗口被销毁（item 为 null），但键盘在用户眼里是开着的。
        // 不算进来的话，状态栏小部件 / ipc toggle 会以为键盘没开、
        // 反而去 showKeyboard()，永远收不起来。
        root.voiceMinimal || root.minimized
        || (dockedLoader.item && dockedLoader.item.keyboardVisible)
        || (floatingLoader.item && floatingLoader.item.keyboardVisible)

    function showKeyboard(restoreLastMode) {
        // 从最小化恢复（或任何途径打开键盘）都要退出最小化，
        // 否则小圆按钮会和键盘同时在场
        root.minimized = false
        const loader = root.floating ? floatingLoader : dockedLoader
        if (!loader.item)
            loader.active = true
        if (!loader.item) {
            console.error("[Inline Keyboard] 窗口实例创建失败，无法显示键盘:", root.floating ? "floating" : "docked")
            return
        }
        loader.item.show()
        // 打开 / 切换停靠↔浮动都回到主键盘页，别停在上次的编辑态或功能页。
        // ⚠ mode 必须改 daemon 自己的属性：直接写 card.mode 会**打断**
        // window→card 的绑定，之后 setMode 就再也传不进去了（踩过）
        root.mode = "keys"
        const card = loader.item.cardRef
        if (card)
            card.editing = false
        root.open = true
        PluginService.setGlobalVar(root.pluginId, "open", true)
        // 打开瞬间先取一次输入法状态，不用等定时器
        root.refreshImState()
        // 恢复上次关闭时的形态。延后一拍：现在窗口刚建好，立刻最小化
        // 会把刚起来的实例又拆掉。
        // 从最小化按钮恢复时传 false：否则读到 lastMode="minimized" 的瞬间
        // 又把自己最小化，圆按钮永远点不开。
        if (restoreLastMode !== false) {
            const lastMode = PluginService.loadPluginData(root.pluginId, "lastMode", "keys")
            if (lastMode === "voice" && root.voiceAvailable)
                Qt.callLater(root.toggleVoice)
            else if (lastMode === "minimized")
                Qt.callLater(root.minimizeKeyboard)
        }
    }

    // ---- 键盘开关 ↔ addon 的 flag 文件 ----
    // addon 每次 tick 都会 syncMode()：flag 在就 setShown(true)（接管候选窗），
    // 不在就 setShown(false)（把候选窗还给 classicui）。
    // 这个文件以前根本没人写，所以 addon 一直认为键盘是关着的 ——
    // 收起后 classicui 接管不了、打开时两者来回抢，都是这个原因。
    Process {
        id: flagWriter
        command: ["true"]
    }

    /**
     * 写 addon 读的那个 flag 文件（决定它是否接管输入法 UI）。
     *
     * 判据是 open && !minimized，不是单独的 open：
     *   · open=false            → 键盘关掉，交还 UI
     *   · open=true  + 最小化   → 键盘逻辑上开着，但界面上只剩一个小按钮，
     *                             同样要交还 UI，否则候选窗被一个看不见的键盘占着
     *   · open=true  + 正常     → 接管 UI
     */
    function syncKeyboardFlag() {
        const ownsUi = root.open && !root.minimized
        flagWriter.command = ["sh", "-c", ownsUi
            ? "touch \"$XDG_RUNTIME_DIR/inline-keyboard-active\""
            : "rm -f \"$XDG_RUNTIME_DIR/inline-keyboard-active\""]
        flagWriter.running = true
    }

    onOpenChanged: syncKeyboardFlag()
    onMinimizedChanged: syncKeyboardFlag()

    Component.onCompleted: {
        root.migrateBuiltinActions()
        root.migrateWinKeyStyle()
        root.syncKeyboardFlag()
    }

    function hideKeyboard() {
        // 先记下关闭时是哪种形态，下次打开接着用（此时还没清理状态）
        const lastMode = root.minimized ? "minimized" : (root.voiceActive ? "voice" : "keys")
        root.lastSelfSaveAt = Date.now()
        PluginService.savePluginData(root.pluginId, "lastMode", lastMode)
        // 键盘关掉就别让麦克风继续录
        root.stopVoice()
        root.minimized = false
        if (dockedLoader.item)
            dockedLoader.item.hide()
        if (floatingLoader.item)
            floatingLoader.item.hide()
        root.open = false
        PluginService.setGlobalVar(root.pluginId, "open", false)
    }

    // 关闭后延迟销毁窗口；这期间又被打开过就不销毁
    readonly property var dockedLoaderItem: dockedLoader.item
    readonly property var floatingLoaderItem: floatingLoader.item

    // 当前活动的键盘卡片（dock / float 两个 LazyLoader 之一）
    // 两个名字都在：daemon 上是 floating（真实状态，会持久化），
    // card 上是 isFloating（由窗口传进去，给 actionStates 判断激活态用）。
    // 这里必须读 floating —— 写成 isFloating 会读到 undefined，
    // 浮动模式下 activeCard 永远是 null，调试 IPC 全失效。
    readonly property var activeCard: {
        const win = root.floating ? floatingLoader.item : dockedLoader.item
        return win ? win.cardRef : null
    }

    // 停靠 / 浮动 之间切换（IpcHandler 和功能页动作都走这里）
    function toggleFloating() {
        root.floating = !root.floating
        root.hideKeyboard()
        Qt.callLater(root.showKeyboard)
    }

    function releaseIdleWindows() {
        if (root.keyboardVisible)
            return
        root.destroyKeyboards()
    }

    // ---- 修饰键：状态机和流转都在 KeyRouter ----
    function stateSummary() { return keyRouter.stateSummary() }

    // ---- 窗口信号落盘：停靠 / 浮动两个实例共用同一套实现 ----
    // 自己最后一次写盘的时间（用来避免 reload 抢在写盘前面覆盖内存）
    property double lastSelfSaveAt: 0

    function saveQuickBar(list) {
        root.lastSelfSaveAt = Date.now()
        root.quickBarActions = list
        PluginService.savePluginData(root.pluginId, "quickBarActions", list)
    }

    function saveOrder(list) {
        root.lastSelfSaveAt = Date.now()
        root.actions = list
        PluginService.savePluginData(root.pluginId, "actions", list)
    }

    function saveSlot(actionId) {
        root.lastSelfSaveAt = Date.now()
        root.slotActionId = actionId
        PluginService.savePluginData(root.pluginId, "slotActionId", actionId)
    }

    function requestImSwitch() {
        // 走自己的平铺列表循环（不只换输入法，也覆盖 rime 的中英文态）
        root.cycleIm()
    }

    // 输入法清单由 addon 在键盘打开时主动推（imlist: 消息），这里不需要主动拉。
    function requestImList() {}


    // 切中英文：用 rime 自己的 D-Bus 接口。
    // 不用 ydotool 发 Shift —— 键盘窗口持焦点时那个 Shift 落不到输入框里，
    // rime 收不到（实测点了没反应）。
    function setImAscii(want) {
        root.runCommand(["busctl", "--user", "call",
            "org.fcitx.Fcitx5", "/rime", "org.fcitx.Fcitx.Rime1",
            "SetAsciiMode", "b", want ? "true" : "false"])
    }

    function toggleImAscii() {
        root.setImAscii(!root.imAsciiMode)
    }

    // 选中某个输入法的某个状态：先切输入法，等它真正生效后再校正中英文。
    // 不能当场判断——fcitx5 切输入法是异步的，此刻 fcitxImName/imAsciiMode 还是旧值。
    property bool pendingAscii: false
    property bool hasPendingAscii: false

    Timer {
        id: asciiFixTimer
        interval: 700   // 等 fcitx5 切完并把新状态推回来
        repeat: false
        onTriggered: {
            if (!root.hasPendingAscii)
                return
            root.hasPendingAscii = false
            if (root.pendingAscii !== root.imAsciiMode)
                root.setImAscii(root.pendingAscii)
        }
    }

    function selectImMode(name, wantAscii) {
        root.selectIm(name)
        // selectIm 里挂的是中文行，切到 ascii 时要换成对应行（标签是 abc）
        if (wantAscii)
            root.optimisticTo(root.imRows.find(r => r.name === name && r.ascii))
        // 等 fcitx5 切完输入法再设子模式：切输入法是异步的，
        // 立刻设会在旧输入法上生效（rs 切完就是中文，不用再设）。
        root.pendingAscii = wantAscii
        root.hasPendingAscii = true
        asciiFixTimer.restart()
    }

    // 平铺的输入法/子模式列表：地球键循环切换和下拉列表共用同一份数据，
    // 两处各写一套是「点了没反应」「高亮对不上」的常见来源。
    // 构造逻辑在 data.js 的 buildImRows（有单测覆盖 current 唯一性）。

    // 地球键单击：循环到列表里的下一项（不只是换输入法，也覆盖 rime 的中英文态）
    function cycleIm() {
        // 下标计算在 data.js 的 nextImRow：current 标错会让地球键原地打转，
        // 那条逻辑有单测（连续点一圈必须回到起点）。
        const next = Data.nextImRow(root.imRows)
        if (next === null) {
            root.requestImList()
            return
        }
        // 先把目标项的图标挂上去，别等 D-Bus 往返
        root.optimisticTo(next)
        if (next.keyboard)
            root.selectIm(next.name)
        else
            root.selectImMode(next.name, next.ascii)
    }

    // 切到某一项时先把它该显示的图标/标签挂上去（乐观显示）。
    // row 是 imRows 里的一项；找不到就只压标签、图标保持原样。
    function optimisticTo(row) {
        if (!row) {
            return
        }
        root.optimisticImLabel = row.label || ""
        root.optimisticImIcon = row.icon || ""
        // 同时记住目标在 imRows 里的行号：连续点击时用它算「下一个」，
        // 否则真实的 imName/imLabel 还没追上，每次点都算出同一项
        let idx = -1
        for (let i = 0; i < root.imRows.length; i++) {
            const r = root.imRows[i]
            if (r.name === row.name && r.ascii === row.ascii && r.keyboard === row.keyboard) {
                idx = i
                break
            }
        }
        fcitxBridge.optimisticImIdx = idx
        root.optimisticImActive = true
        optimisticImTimer.restart()
    }

    function selectIm(name) {
        // 乐观显示：中文行（非 ascii）的标签/图标先顶上
        root.optimisticTo(root.imRows.find(r => r.name === name && !r.ascii))

        // 走 fcitx5 官方 D-Bus。
        // addon 里不能切：fcitx5 的 setCurrentInputMethod / enumerate 在第三方
        // addon 里（键盘窗口抢占焦点后）调用一律 ABORT，两种 API 都实测崩过。
        // 所以这里用 Controller1.SetCurrentIM —— 它就是控制台里
        // `fcitx5-remote -s` 走的同一条路，不受焦点影响。
        root.runCommand(["busctl", "--user", "call",
            "org.fcitx.Fcitx5", "/controller",
            "org.fcitx.Fcitx.Controller1", "SetCurrentIM", "s", name])
    }

    // 输入法名字/图标由 addon 主动推（state: 消息），不需要主动刷新。
    // 保留空实现：几个调用点（窗口显示时）不用改。
    function refreshImState() {}

    // 窗口自己收起时（点收起键 / 动作里的 close）同步全局状态
    function onKeyboardClosed() {
        root.open = false
        PluginService.setGlobalVar(root.pluginId, "open", false)
        Qt.callLater(root.releaseIdleWindows)
    }

    LazyLoader {
        id: dockedLoader
        active: false

        KeyboardWindow {
            kbWidth: root.kbWidth
            kbHeight: root.kbHeight
            avoidWindows: root.avoidWindows
            voiceActive: root.voiceActive
            voiceMinimal: root.voiceMinimal
            voiceAvailable: root.voiceAvailable
            bgOpacity: root.bgOpacity
            keyOpacity: root.keyOpacity
            onOpacityAdjusted: (bg, key) => {
                root.bgOpacity = bg
                root.keyOpacity = key
            }
            specialKeyStyle: root.specialKeyStyle
            winKeyStyle: root.winKeyStyle
            winKeyCustomIcon: root.winKeyCustomIcon
            resizeW: root.resizeW
            resizeH: root.resizeH
            baseKbWidth: root.baseKbWidth
            baseKbHeight: root.baseKbHeight
            onResizeCommitRequested: root.commitResize()
            onResizeCloseRequested: root.closeResize()
            onResizeCancelRequested: root.cancelResize()
            onResizeResetRequested: root.resetResize()
            onResizeFillToggleRequested: root.toggleDockFill()
            onVoiceMinimalRequested: root.toggleVoiceMinimal()
            onVoiceMicRequested: root.voiceMicPressed()
            onModeChangeRequested: mode => {
                if (mode === "transparency")
                    root.enterTransparency()   // 面板需要进入前的快照
                else
                    root.mode = mode
            }
            dockFill: root.dockFill
            actionList: root.actions
            fcitxCandidates: root.fcitxCandidates
            fcitxImKeyboard: root.fcitxImKeyboard
            fcitxHasMore: root.fcitxHasMore
            fcitxImIcon: root.fcitxImIcon
            fcitxImLabel: root.fcitxImLabel
            fcitxPreeditEmbedded: root.fcitxPreeditEmbedded
            debugCandItems: root.debugCandItems
            allCandidates: root.allCandidates
            candRevision: root.candRevision
            fcitxPreedit: root.fcitxPreedit
            fcitxVisible: root.fcitxVisible
            repeatInterval: root.repeatInterval
            slotActionId: root.slotActionId
            quickBarActions: root.quickBarActions
            fnActive: root.fnActive
            escSwap: root.escSwap
            modifierStates: root.modifierStates
            page: root.page
            mode: root.mode
            editing: root.editing
            imList: root.imList
            // addon 给了图标路径就直接用（内嵌状态没有托盘图标可用），
            // 否则才看托盘抓图是否成功
            onQuickBarChanged: list => root.saveQuickBar(list)
            onOrderChanged: list => root.saveOrder(list)
            onSlotChanged: actionId => root.saveSlot(actionId)
            onEditingChanged: root.editing = editing
            onQuickAction: action => root.handleQuick(action)
            onImSwitchRequested: root.requestImSwitch()
            onImListRequested: root.requestImList()
            onImCycleRequested: root.cycleIm()
            onSelectCandidateRequested: index => root.selectCandidateByIndex(index)
            onImSelected: name => root.selectIm(name)
            onKeyPressed: keyData => {
                root.handleKey(keyData)
            }
            onModifierPressed: keyData => root.modifierPress(keyData)
            onModifierReleased: keyData => root.modifierRelease(keyData)
            onTextCommitRequested: text => root.typeText(text)
            onAllCandidatesRequested: fcitxBridge.requestAllCandidates()
            onKeyboardClosed: root.onKeyboardClosed()
        }
    }

    LazyLoader {
        id: floatingLoader
        active: false

        FloatingKeyboardWindow {
            controller: root
            kbWidth: root.kbWidth
            kbHeight: root.kbHeight
            fnActive: root.fnActive
            escSwap: root.escSwap
            modifierStates: root.modifierStates
            page: root.page
            mode: root.mode
            editing: root.editing
            avoidWindows: root.avoidWindows
            voiceActive: root.voiceActive
            voiceMinimal: root.voiceMinimal
            voiceAvailable: root.voiceAvailable
            bgOpacity: root.bgOpacity
            keyOpacity: root.keyOpacity
            onOpacityAdjusted: (bg, key) => {
                root.bgOpacity = bg
                root.keyOpacity = key
            }
            specialKeyStyle: root.specialKeyStyle
            winKeyStyle: root.winKeyStyle
            winKeyCustomIcon: root.winKeyCustomIcon
            resizeW: root.resizeW
            resizeH: root.resizeH
            baseKbWidth: root.baseKbWidth
            baseKbHeight: root.baseKbHeight
            onResizeCommitRequested: root.commitResize()
            onResizeCloseRequested: root.closeResize()
            onResizeCancelRequested: root.cancelResize()
            onResizeResetRequested: root.resetResize()
            onResizeFillToggleRequested: root.toggleDockFill()
            onVoiceMinimalRequested: root.toggleVoiceMinimal()
            onVoiceMicRequested: root.voiceMicPressed()
            onModeChangeRequested: mode => {
                if (mode === "transparency")
                    root.enterTransparency()   // 面板需要进入前的快照
                else
                    root.mode = mode
            }
            dockFill: root.dockFill
            actionList: root.actions
            fcitxCandidates: root.fcitxCandidates
            fcitxImKeyboard: root.fcitxImKeyboard
            fcitxHasMore: root.fcitxHasMore
            fcitxImIcon: root.fcitxImIcon
            fcitxImLabel: root.fcitxImLabel
            fcitxPreeditEmbedded: root.fcitxPreeditEmbedded
            debugCandItems: root.debugCandItems
            allCandidates: root.allCandidates
            candRevision: root.candRevision
            fcitxPreedit: root.fcitxPreedit
            fcitxVisible: root.fcitxVisible
            repeatInterval: root.repeatInterval
            slotActionId: root.slotActionId
            quickBarActions: root.quickBarActions
            imList: root.imList
            // addon 给了图标路径就直接用（内嵌状态没有托盘图标可用），
            // 否则才看托盘抓图是否成功

            onQuickBarChanged: list => root.saveQuickBar(list)
            onOrderChanged: list => root.saveOrder(list)
            onSlotChanged: actionId => root.saveSlot(actionId)
            onEditingChanged: root.editing = editing
            onQuickAction: action => root.handleQuick(action)
            onImSwitchRequested: root.requestImSwitch()
            onImListRequested: root.requestImList()
            onImCycleRequested: root.cycleIm()
            onSelectCandidateRequested: index => root.selectCandidateByIndex(index)
            onImSelected: name => root.selectIm(name)
            onKeyPressed: keyData => {
                root.handleKey(keyData)
            }
            onModifierPressed: keyData => root.modifierPress(keyData)
            onModifierReleased: keyData => root.modifierRelease(keyData)
            onTextCommitRequested: text => root.typeText(text)
            onAllCandidatesRequested: fcitxBridge.requestAllCandidates()
            onKeyboardClosed: root.onKeyboardClosed()
        }
    }

    // 语音模式：一条浮动的胶囊，只显示语音行。
    // 和 FloatingKeyboardWindow 是两种不同布局，不是同一个窗口收窄。
    VoiceMiniWindow {
        controller: root
    }

    // 最小化模式：屏幕角上一个浮动的小圆按钮
    MiniKeyboardWindow {
        controller: root
    }

    IpcHandler {
        target: "inlineKeyboard"

        function toggle(): string {
            if (root.keyboardVisible) {
                root.hideKeyboard()
                return "INLINE_KEYBOARD_CLOSED"
            }
            root.showKeyboard()
            return "INLINE_KEYBOARD_OPENED"
        }

        function open(): string {
            root.showKeyboard()
            return "INLINE_KEYBOARD_OPENED"
        }

        function close(): string {
            root.hideKeyboard()
            return "INLINE_KEYBOARD_CLOSED"
        }

        function toggleFloat(): string {
            root.toggleFloating()
            return root.floating ? "INLINE_KEYBOARD_FLOATING" : "INLINE_KEYBOARD_DOCKED"
        }

        function debugCardHeight(): string {
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
            if (!card)
                return "INLINE_KEYBOARD_H:-1"
            // win 的高度才决定 exclusiveZone；card 自己没有 implicitHeight
            const win = root.floating ? root.floatingLoaderItem
                                      : root.dockedLoaderItem
            return "INLINE_KEYBOARD_H:card=" + Math.round(card.height)
                   + ":win=" + (win ? Math.round(win.implicitHeight) : "-")
                   + ":zone=" + (win ? Math.round(win.exclusiveZone) : "-")
                   + ":kbHeight=" + Math.round(root.kbHeight)
                   + ":page=" + root.page + ":mode=" + root.mode
        }

        function setPage(p: string): string {
            return "INLINE_KEYBOARD_PAGE:" + root.setPage(p)
        }

        // 调试用：表情页的段 / 分类（写的是卡片上的属性，和点分类条效果一致）
        function setEmojiFilter(segment: string, category: string): string {
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
            if (!card)
                return "INLINE_KEYBOARD_EMOJI:no-card"
            if (segment)
                card.emojiSegment = segment
            if (category)
                card.emojiCategory = category
            return "INLINE_KEYBOARD_EMOJI:" + card.emojiSegment + ":" + card.emojiCategory
        }

        // 调试用：走和点表情一模一样的上屏通路（addon commit / 剪贴板兜底）
        function typeText(text: string): string {
            if (!root.devMode) return "dev mode off"
            return "INLINE_KEYBOARD_TEXT:" + root.typeText(text)
                   + ":" + root.lastTextCommitVia
        }

        // 调试用：走和触摸换页键完全相同的入口（卡片 → handleKey），
        // 验证换页分发而不是绕过它。setPage 是直接赋值，绕过 handleKey。
        function pressPageKey(to: string): string {
            if (!root.devMode) return "dev mode off"
            root.handleKey({k: "page", to: to})
            return "INLINE_KEYBOARD_PAGE:" + root.page
        }

        // 调试用：直接切 Fn 层（鼠标点击在 layer-shell 上还没验证通过）
        function toggleFn(): string {
            root.setModifierState("fn", root.fnState > 0 ? 0 : 2)
            return root.fnActive ? "INLINE_KEYBOARD_FN_ON" : "INLINE_KEYBOARD_FN_OFF"
        }

        // 调试用：直接设修饰键状态（0 未激活 / 1 一次性 / 2 锁定），自测高亮用
        function setModifier(name: string, state: int): string {
            if (!root.devMode) return "dev mode off"
            root.setModifierState(name, state)
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        // 调试用：等于点一下某个修饰键（走和触摸完全相同的 cycleModifier）
        function tapModifier(name: string): string {
            if (!root.devMode) return "dev mode off"
            root.cycleModifier(name)
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        // 调试用：按住 / 松开修饰键（noLock 模式靠这两个）
        function pressModifier(name: string): string {
            if (!root.devMode) return "dev mode off"
            root.modifierPress(Modifiers.keyDataFor(name))
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        function releaseModifier(name: string): string {
            if (!root.devMode) return "dev mode off"
            root.modifierRelease(Modifiers.keyDataFor(name))
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }




        // 调试用：模拟按一个普通键（键码），返回所有修饰键状态
        function pressDebugKey(code: int, sym: string): string {
            if (!root.devMode) return "dev mode off"
            // 带键名才会走 socket 直通；不带时退回 ydotool（和真实按键一致）
            root.handleKey({ k: "char", c: code, l: sym })
            return root.stateSummary()
        }

        // 调试：绕过卡片直接走 socket 直通，用来单独验证这条通道
        function debugDirectKey(sym: string): string {
            if (!root.devMode) return "dev mode off"
            const ok = root.sendFcitx("key:" + sym)
            return "INLINE_KEYBOARD_DIRECT:" + sym + ":sent=" + ok
                + ":engine=" + (!root.fcitxImKeyboard)
                + ":combo=" + root.hasComboModifier
        }

        function modifierStates(): string {
            if (!root.devMode) return "dev mode off"
            return root.stateSummary()
        }

        // 调试用：切修饰键切换方式（noLock / toggle / tapLock / doubleTapLock）
        function setModifierMode(mode: string): string {
            if (!root.devMode) return "dev mode off"
            root.modifierMode = mode
            root.clearModifierStates()
            return "INLINE_KEYBOARD_MODIFIER_MODE:" + root.modifierMode
        }

        // 调试用：keys / functions 之间切换
        // 临时：走用户的真实路径（点动作 → handleQuick → beginResize）
        // 调试：等价于点语音行右侧的麦克风（走 voiceMicPressed 那条路）
        function debugVoiceMic(): string {
            if (!root.devMode) return "dev mode off"
            root.voiceMicPressed()
            return "voice=" + (root.voiceActive ? "rec" : "idle")
                + "/" + (root.voiceMinimal ? "mini" : "full")
        }

        // 调试：直接切语音模式（等价于点语音行左侧按钮）
        function debugVoiceMinimal(on: bool): string {
            if (!root.devMode) return "dev mode off"
            if (root.voiceMinimal !== on)
                root.toggleVoiceMinimal()
            return "minimal=" + root.voiceMinimal + " floating=" + root.floating
        }

        function debugMinimize(): string {
            if (!root.devMode) return "dev mode off"
            root.toggleMinimize()
            return "min=" + (root.minimized ? 1 : 0) + " open=" + root.open
        }

        function debugQuickAction(id: string): string {
            if (!root.devMode) return "dev mode off"
            root.handleQuick(id)
            const card = root.activeCard
            return "mode=" + (card ? card.mode : "-")
                + " page=" + (card ? card.page : "-")
                + " listOpen=" + (card ? card.candListOpen : "-")
        }

        function setMode(m: string): string {
            if (!root.devMode) return "dev mode off"
            root.mode = m
            return "INLINE_KEYBOARD_MODE:" + m
        }

        // 恢复默认动作表
        function resetActions(): string {
            if (!root.devMode) return "dev mode off"
            root.actions = root.defaultActions
            root.slotActionId = "float"
            PluginService.savePluginData(root.pluginId, "actions", root.defaultActions)
            PluginService.savePluginData(root.pluginId, "slotActionId", "float")
            return "INLINE_KEYBOARD_ACTIONS_RESET"
        }

        // 调试用：动作列表编辑态
        function setEditing(v: bool): string {
            if (!root.devMode) return "dev mode off"
            root.editing = v
            return "INLINE_KEYBOARD_EDITING:" + v
        }

        // 调试用：模拟「把列表第 index 个动作拖到卡片坐标 (x,y)」，
        // 用来在没有人手的情况下检查拖动预览（幽灵块 / 让位 / 挤出）
        function debugDrag(index: int, x: real, y: real): string {
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
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

        // 调试用：一次导出卡片 / daemon 的关键数组长度，定位「该显示的不显示」类问题
        // 一行诊断串。排查键盘问题时这是第一个该看的东西：
        // socket / 输入法 / 候选数 / 预编辑 / ydotool / 修饰键状态。
        // 注意不能用可选链 ?. —— QML 的 JS 引擎不支持，整个文件会语法错误。
        function diag(): string {
            const parts = []
            parts.push("open=" + root.open)
            parts.push("floating=" + root.floating)
            parts.push("socket=" + root.fcitxSocketUp)
            parts.push("op=" + Math.round(root.bgOpacity * 100) + "/" + Math.round(root.keyOpacity * 100))
            parts.push("addonLog=" + root.fcitxLastError)
            parts.push("im=" + root.fcitxImName + "/" + root.fcitxImLabel
                       + (root.fcitxImKeyboard ? "(kb)" : "(ime)"))
            parts.push("imList=" + root.imList.length)
            const currentRow = root.imRows.find(r => r.current)
            parts.push("imRows=" + root.imRows.length
                       + " cur=" + (currentRow ? currentRow.label : "-"))
            parts.push("sel=" + (root.activeCard ? root.activeCard.lastSelectInfo : "-"))
        // QML 侧真正显示给用户的输入法标签/图标（含乐观值）
        parts.push("qLabel=" + root.fcitxImLabel)
        parts.push("opt=" + (root.optimisticImActive ? "1" : "0"))
        parts.push("saved=" + Math.round(root.savedW) + "x" + Math.round(root.savedH))
        parts.push("dockFill=" + (root.dockFill ? 1 : 0))
        parts.push("voice=" + (root.voiceActive ? "rec" : "idle")
                   + "/" + (root.voiceMinimal ? "mini" : "full"))
        parts.push("vAvail=" + (root.voiceAvailable ? 1 : 0))
        parts.push("min=" + (root.minimized ? 1 : 0))
        parts.push("cardW=" + Math.round(root.activeCard ? root.activeCard.width : -1))
        parts.push("mode=" + (root.activeCard ? root.activeCard.mode : "-"))
        parts.push("handles=" + (root.activeCard && root.activeCard.candListPanel
            ? "-" : "-"))
        parts.push("isFloat=" + (root.activeCard && root.activeCard.isFloating ? 1 : 0))
            parts.push("candListOpen="
                       + (root.activeCard ? root.activeCard.candListOpen : "-")
                       + " loaderActive="
                       + (root.activeCard
                          ? (root.activeCard.children.length > 0 ? "?" : "?") : "-"))
            parts.push("cand=" + root.fcitxCandidates.length
                       + " dbg=" + root.debugCandItems.length
                       + " all=" + root.allCandidates.length)
            parts.push("preedit=" + JSON.stringify(root.fcitxPreedit))
            parts.push("ydotoold=" + root.ydotooldUp)
            parts.push("winKey=" + root.winKeyStyle + "/"
                       + (root.winKeyCustomIcon !== "" ? root.winKeyCustomIcon : "-")
                       + " special=" + root.specialKeyStyle)
            // 卡片实际收到的值：daemon → 窗口 → 卡片这条链断一次就白搭
            // （踩过：窗口声明了 winKeyCustomIcon 却没传给 KeyboardCard）
            parts.push("cardWin=" + (root.activeCard
                       ? (root.activeCard.winKeyStyle + "/"
                          + (root.activeCard.winKeyCustomIcon || "-")) : "-"))
            parts.push("cardGeom=" + (root.activeCard
                       ? (Math.round(root.activeCard.width) + "x"
                          + Math.round(root.activeCard.height)
                          + "@" + Math.round(root.activeCard.y)
                          + " page=" + root.activeCard.page) : "-"))
            parts.push("mods=" + root.stateSummary())
            parts.push("lastError=" + (root.lastError || "-"))
            return parts.join(" | ")
        }

        // dms ipc call inlineKeyboard debugCand "一,二,三" 注入假候选；空串清除
        // 参数必须标类型：不标会被推断成 QVariant，DMS 的 IPC
        // 直接拒收（Error parsing function "debugCand": Type of argument 1
        // (csv: QVariant) cannot be used across IPC）。
        function debugCand(csv: string): string {
            if (!root.devMode) return "dev mode off"
            const text = String(csv || "")
            root.debugCandItems = text === ""
                ? [] : text.split(",").map(s => s.trim()).filter(s => s !== "")
            return root.debugCandItems.length + " 项"
        }

        // dms ipc call inlineKeyboard debugCandList   切换候选列表页
        function debugCandList(): string {
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
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
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
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
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
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
        }

        function debugRows(): string {
            if (!root.devMode) return "dev mode off"
            let out = ["im=" + root.fcitxImName,
                       "ascii=" + root.imAsciiMode,
                       "list=" + root.imList.length,
                       "rows=" + root.imRows.length]
            for (let i = 0; i < root.imRows.length; i++) {
                const r = root.imRows[i]
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
            if (!root.devMode) return "dev mode off"
            root.cycleIm()
            return "im=" + root.fcitxImName
                + " rows=" + root.imRows.length
                + " list=" + root.imList.length
        }


        // 调试用：直接走 handleQuick 执行一次动作（验证自定义动作的命令链路）
        // 调试：直接把一次按键交给 handleKey（模拟点键盘）
        function debugKey(kind: string, to: string): string {
            if (!root.devMode) return "dev mode off"
            root.handleKey({ k: kind, to: to })
            return "INLINE_KEYBOARD_KEY:" + kind + ":to=" + to + ":page=" + root.page
        }

        // 调试：直接注入一个键码（不经过卡片，方便无触摸屏验证输入后端）
        function debugType(code: string): string {
            if (!root.devMode) return "dev mode off"
            root.injectKey(Number(code))
            return "INLINE_KEYBOARD_TYPE:" + code + ":ydotoold=" + (root.ydotooldUp ? "up" : "down")
        }

        function debugRunAction(id: string): string {
            if (!root.devMode) return "dev mode off"
            const action = root.actionById(id)
            if (!action)
                return "INLINE_KEYBOARD_NO_ACTION:" + id
            root.handleQuick(id)
            return "INLINE_KEYBOARD_RAN:" + id + ":cmd=" + (action.cmd || "")
        }

        // 调试用：写一个带命令的自定义动作（用于验证 cmd 链路）
        function debugAddCommandAction(label: string, icon: string, cmd: string): string {
            if (!root.devMode) return "dev mode off"
            const list = Actions.toArray(root.actions).slice()
            list.push({
                id: "u" + Date.now(),
                label: label,
                icon: icon || "bolt",
                cmd: cmd || "",
                hidden: false,
                builtin: false
            })
            root.actions = list
            root.saveOrder(list)
            return "INLINE_KEYBOARD_ADDED:" + label
        }

        // 调试用：生成 count 个占位动作（测滚动、容量、拖放用）。
        // 同时清空固定栏和槽，避免它们指向已经不存在的 id。
        function debugSetActions(count: int): string {
            if (!root.devMode) return "dev mode off"
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
            root.actions = list
            root.saveOrder(list)
            root.quickBarActions = []
            root.saveQuickBar([])
            root.slotActionId = ""
            root.saveSlot("")
            return "INLINE_KEYBOARD_ACTIONS:" + list.length
        }

        // 调试用：模拟「从固定栏第 index 个动作拖到卡片坐标 (x,y)」
        function debugDragFromBar(index: int, x: real, y: real): string {
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
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
            if (!root.devMode) return "dev mode off"
            const card = root.activeCard
            if (!card)
                return "INLINE_KEYBOARD_NO_CARD"
            card.endDrag()
            return "INLINE_KEYBOARD_DROPPED"
        }

        // 调试用：直接设置固定栏动作（逗号分隔的动作 id），验证编辑态视觉用
        function setQuickBar(ids: string): string {
            if (!root.devMode) return "dev mode off"
            const wanted = String(ids || "").split(",").map(s => s.trim()).filter(s => s !== "")
            const byId = ({})
            const list = root.actions || []
            for (let i = 0; i < list.length; i++)
                byId[list[i].id] = list[i]
            const bar = []
            for (let i = 0; i < wanted.length; i++) {
                if (byId[wanted[i]])
                    bar.push(byId[wanted[i]])
            }
            root.quickBarActions = bar
            root.saveQuickBar(bar)
            return "INLINE_KEYBOARD_QUICKBAR:" + bar.map(a => a.id).join(",")
        }
    }
}
