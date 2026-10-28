// Inline Keyboard 的守护插件：唯一持有持久状态的地方。
// 职责：读写插件设置与运行状态、提供 IPC 命令、按需创建/销毁两个键盘窗口、
// 向卡片下发动作表与设置。fcitx5 通信在 FcitxBridge、按键路由在 KeyRouter。
// 卡片和窗口不直接读配置文件，全部通过这里的属性和信号。

import QtQuick
import "data.js" as Data
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
        actions: root.actions
        modifierMode: root.modifierMode
    }

    // ---- 状态（窗口销毁后仍保留）----
    property bool open: PluginService.getGlobalVar(root.pluginId, "open", false)
    property bool floating: PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
    property bool avoidWindows: PluginService.loadPluginData(root.pluginId, "avoidWindows", true)
    readonly property bool fnActive: root.fnState > 0
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
    readonly property alias fcitxVisible: fcitxBridge.panelVisible
    readonly property alias fcitxImKeyboard: fcitxBridge.imKeyboard
    readonly property alias fcitxImName: fcitxBridge.imName
    readonly property alias fcitxImLabel: fcitxBridge.imLabel
    readonly property alias fcitxImIcon: fcitxBridge.imIcon
    readonly property alias fcitxHasPrev: fcitxBridge.hasPrev
    readonly property alias fcitxHasMore: fcitxBridge.hasMore
    readonly property alias fcitxSocketUp: fcitxBridge.socketUp
    readonly property alias fcitxLastError: fcitxBridge.lastError
    readonly property alias imList: fcitxBridge.imList
    readonly property alias imRows: fcitxBridge.imRows
    readonly property alias imAsciiMode: fcitxBridge.isAsciiMode

    // 预编辑是否由应用自己画（fcitx5 的 clientPreedit 非空）。
    // 为 true 时输入框里已经有拼音串了，键盘不要再重复显示。
    // 预编辑去重的实现先撤了：属性保留给 UI 引用，值恒 false，
    // 键盘照常画自己的预编辑行。
    readonly property bool fcitxPreeditEmbedded: false

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
                : "Cannot insert text: install the fcitx5 addon (inline-keyboard-status) or wl-clipboard"
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
    function handleQuick(action) {
        // 自定义动作：跑它自己的命令（用户自己写的，等同桌面启动器）
        const custom = root.actionById(action)
        if (custom && custom.cmd && custom.cmd.trim() !== "") {
            root.runCommand(["sh", "-c", custom.cmd])
            return
        }
        switch (action) {
        case "close":
            root.hideKeyboard()
            return
        case "float":
            root.toggleFloating()
            return
        case "settings":
            // 直接打开本插件的设置页（tab 名是 "plugin:<id>"）
            root.runCommand(["dms", "ipc", "call", "settings", "openWith", "plugin:inlineKeyboard"])
            return
        case "nextIm":
            root.cycleIm()
            return
        case "clipboard":
            root.runCommand(["dms", "ipc", "call", "clipboard", "toggle"])
            return
        case "mic":
            root.notifyUnimplemented("Voice input")
            return
        case "size":
            root.notifyUnimplemented("Size")
            return
        case "avoid":
            // 停靠模式下是否让其它窗口避让键盘（改 layer-shell 的独占区）
            root.avoidWindows = !root.avoidWindows
            PluginService.savePluginData(root.pluginId, "avoidWindows", root.avoidWindows)
            return
        case "undo":
            root.runCommand(["ydotool", "key", "29:1", "44:1", "44:0", "29:0"])
            return
        case "redo":
            root.runCommand(["ydotool", "key", "29:1", "42:1", "44:1", "44:0", "42:0", "29:0"])
            return
        default: {
            const def = root.findAction(action)
            if (def && def.cmd) {
                root.runCommand(["sh", "-c", def.cmd])
                return
            }
            console.error("[Inline Keyboard] quick action 未实现:", action)
        }
        }
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
        return (v && v.length) ? root.sanitizeActions(v) : root.defaultActions
    }

    // 按 id 去重（避免拖动过程中重复写入）
    // 清洗外部配置（去重/去无效项）；实现与单测在 actions.js
    function sanitizeActions(list) {
        return Actions.sanitizeActions(list, root.defaultActions)
    }

    // 外观：缩放 + 透明度，都从设置读（PluginSettings 存的是百分数）
    property real scale: PluginService.loadPluginData(root.pluginId, "scale", 100) / 100.0
    property real bgOpacity: PluginService.loadPluginData(root.pluginId, "bgOpacity", 100) / 100.0
    property real keyOpacity: PluginService.loadPluginData(root.pluginId, "keyOpacity", 100) / 100.0
    property bool defaultFloating: PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
    // Esc 与 \`~ 键对调（想要 Esc 在左上角的人用）
    property bool escSwap: PluginService.loadPluginData(root.pluginId, "escSwap", false)
    // 键盘名义尺寸（scale = 1 时的大小）。窗口与卡片都按它推按键尺寸
    readonly property real baseKbWidth: 1050
    readonly property real baseKbHeight: 444
    readonly property real kbWidth: baseKbWidth * root.scale
    readonly property real kbHeight: baseKbHeight * root.scale

    Connections {
        target: PluginService
        function onGlobalVarChanged(pluginId, varName) {
            if (pluginId !== root.pluginId || varName !== "open")
                return
            const want = PluginService.getGlobalVar(root.pluginId, "open", false)
            if (want && !root.keyboardVisible)
                root.showKeyboard()
            else if (!want && root.keyboardVisible)
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
        const nextScale = PluginService.loadPluginData(root.pluginId, "scale", 100) / 100.0
        if (nextScale !== root.scale)
            root.scale = nextScale
        const nextBgOpacity = PluginService.loadPluginData(root.pluginId, "bgOpacity", 100) / 100.0
        if (nextBgOpacity !== root.bgOpacity)
            root.bgOpacity = nextBgOpacity
        const nextKeyOpacity = PluginService.loadPluginData(root.pluginId, "keyOpacity", 100) / 100.0
        if (nextKeyOpacity !== root.keyOpacity)
            root.keyOpacity = nextKeyOpacity
        const nextAvoid = PluginService.loadPluginData(root.pluginId, "avoidWindows", true)
        if (nextAvoid !== root.avoidWindows)
            root.avoidWindows = nextAvoid
        const nextDefaultFloating = PluginService.loadPluginData(root.pluginId, "defaultFloating", false)
        if (nextDefaultFloating !== root.defaultFloating) {
            root.defaultFloating = nextDefaultFloating
            // 键盘没打开时，改默认模式立刻作用到下一次打开
            if (!root.keyboardVisible)
                root.floating = nextDefaultFloating
        }
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
        (dockedLoader.item && dockedLoader.item.keyboardVisible) ||
        (floatingLoader.item && floatingLoader.item.keyboardVisible)

    function showKeyboard() {
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

    function syncKeyboardFlag() {
        flagWriter.command = ["sh", "-c", root.open
            ? "touch \"$XDG_RUNTIME_DIR/inline-keyboard-active\""
            : "rm -f \"$XDG_RUNTIME_DIR/inline-keyboard-active\""]
        flagWriter.running = true
    }

    onOpenChanged: syncKeyboardFlag()

    Component.onCompleted: syncKeyboardFlag()

    function hideKeyboard() {
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
    // 属性名是 floating，不是 isFloating —— 后者在重构时删掉了，
    // 这里一直读到一个 undefined，浮动模式下 activeCard 永远是 null（调试 IPC 全失效）
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
        dockedLoader.active = false
        floatingLoader.active = false
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
        if (next.keyboard)
            root.selectIm(next.name)
        else
            root.selectImMode(next.name, next.ascii)
    }

    function selectIm(name) {
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
            bgOpacity: root.bgOpacity
            keyOpacity: root.keyOpacity
            actionList: root.actions
            fcitxCandidates: root.fcitxCandidates
            fcitxImKeyboard: root.fcitxImKeyboard
            fcitxHasMore: root.fcitxHasMore
            fcitxImIcon: root.fcitxImIcon
            fcitxImLabel: root.fcitxImLabel
            fcitxPreeditEmbedded: root.fcitxPreeditEmbedded
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
            onKeyboardClosed: root.onKeyboardClosed()
        }
    }

    LazyLoader {
        id: floatingLoader
        active: false

        FloatingKeyboardWindow {
            kbWidth: root.kbWidth
            kbHeight: root.kbHeight
            fnActive: root.fnActive
            escSwap: root.escSwap
            modifierStates: root.modifierStates
            page: root.page
            mode: root.mode
            editing: root.editing
            avoidWindows: root.avoidWindows
            bgOpacity: root.bgOpacity
            keyOpacity: root.keyOpacity
            actionList: root.actions
            fcitxCandidates: root.fcitxCandidates
            fcitxImKeyboard: root.fcitxImKeyboard
            fcitxHasMore: root.fcitxHasMore
            fcitxImIcon: root.fcitxImIcon
            fcitxImLabel: root.fcitxImLabel
            fcitxPreeditEmbedded: root.fcitxPreeditEmbedded
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
            onKeyboardClosed: root.onKeyboardClosed()
        }
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
            return "INLINE_KEYBOARD_TEXT:" + root.typeText(text)
                   + ":" + root.lastTextCommitVia
        }

        // 调试用：走和触摸换页键完全相同的入口（卡片 → handleKey），
        // 验证换页分发而不是绕过它。setPage 是直接赋值，绕过 handleKey。
        function pressPageKey(to: string): string {
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
            root.setModifierState(name, state)
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        // 调试用：等于点一下某个修饰键（走和触摸完全相同的 cycleModifier）
        function tapModifier(name: string): string {
            root.cycleModifier(name)
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        // 调试用：按住 / 松开修饰键（noLock 模式靠这两个）
        function pressModifier(name: string): string {
            root.modifierPress(Modifiers.keyDataFor(name))
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }

        function releaseModifier(name: string): string {
            root.modifierRelease(Modifiers.keyDataFor(name))
            return "INLINE_KEYBOARD_MODIFIER:" + name + "=" + root.modifierStateOf(name)
        }




        // 调试用：模拟按一个普通键（键码），返回所有修饰键状态
        function pressDebugKey(code: int, sym: string): string {
            // 带键名才会走 socket 直通；不带时退回 ydotool（和真实按键一致）
            root.handleKey({ k: "char", c: code, l: sym })
            return root.stateSummary()
        }

        // 调试：绕过卡片直接走 socket 直通，用来单独验证这条通道
        function debugDirectKey(sym: string): string {
            const ok = root.sendFcitx("key:" + sym)
            return "INLINE_KEYBOARD_DIRECT:" + sym + ":sent=" + ok
                + ":engine=" + (!root.fcitxImKeyboard)
                + ":combo=" + root.hasComboModifier
        }

        function modifierStates(): string {
            return root.stateSummary()
        }

        // 调试用：切修饰键切换方式（noLock / toggle / tapLock / doubleTapLock）
        function setModifierMode(mode: string): string {
            root.modifierMode = mode
            root.clearModifierStates()
            return "INLINE_KEYBOARD_MODIFIER_MODE:" + root.modifierMode
        }

        // 调试用：keys / functions 之间切换
        function setMode(m: string): string {
            root.mode = m
            return "INLINE_KEYBOARD_MODE:" + m
        }

        // 恢复默认动作表
        function resetActions(): string {
            root.actions = root.defaultActions
            root.slotActionId = "float"
            PluginService.savePluginData(root.pluginId, "actions", root.defaultActions)
            PluginService.savePluginData(root.pluginId, "slotActionId", "float")
            return "INLINE_KEYBOARD_ACTIONS_RESET"
        }

        // 调试用：动作列表编辑态
        function setEditing(v: bool): string {
            root.editing = v
            return "INLINE_KEYBOARD_EDITING:" + v
        }

        // 调试用：模拟「把列表第 index 个动作拖到卡片坐标 (x,y)」，
        // 用来在没有人手的情况下检查拖动预览（幽灵块 / 让位 / 挤出）
        function debugDrag(index: int, x: real, y: real): string {
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
            parts.push("addonLog=" + root.fcitxLastError)
            parts.push("im=" + root.fcitxImName + "/" + root.fcitxImLabel
                       + (root.fcitxImKeyboard ? "(kb)" : "(ime)"))
            parts.push("imList=" + root.imList.length)
            const currentRow = root.imRows.find(r => r.current)
            parts.push("imRows=" + root.imRows.length
                       + " cur=" + (currentRow ? currentRow.label : "-"))
            parts.push("cand=" + root.fcitxCandidates.length)
            parts.push("preedit=" + JSON.stringify(root.fcitxPreedit))
            parts.push("ydotoold=" + root.ydotooldUp)
            parts.push("mods=" + root.stateSummary())
            parts.push("lastError=" + (root.lastError || "-"))
            return parts.join(" | ")
        }

        function debugRows(): string {
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
            root.cycleIm()
            return "im=" + root.fcitxImName
                + " rows=" + root.imRows.length
                + " list=" + root.imList.length
        }


        // 调试用：直接走 handleQuick 执行一次动作（验证自定义动作的命令链路）
        // 调试：直接把一次按键交给 handleKey（模拟点键盘）
        function debugKey(kind: string, to: string): string {
            root.handleKey({ k: kind, to: to })
            return "INLINE_KEYBOARD_KEY:" + kind + ":to=" + to + ":page=" + root.page
        }

        // 调试：直接注入一个键码（不经过卡片，方便无触摸屏验证输入后端）
        function debugType(code: string): string {
            root.injectKey(Number(code))
            return "INLINE_KEYBOARD_TYPE:" + code + ":ydotoold=" + (root.ydotooldUp ? "up" : "down")
        }

        function debugRunAction(id: string): string {
            const action = root.actionById(id)
            if (!action)
                return "INLINE_KEYBOARD_NO_ACTION:" + id
            root.handleQuick(id)
            return "INLINE_KEYBOARD_RAN:" + id + ":cmd=" + (action.cmd || "")
        }

        // 调试用：写一个带命令的自定义动作（用于验证 cmd 链路）
        function debugAddCommandAction(label: string, icon: string, cmd: string): string {
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
            const card = root.activeCard
            if (!card)
                return "INLINE_KEYBOARD_NO_CARD"
            card.endDrag()
            return "INLINE_KEYBOARD_DROPPED"
        }

        // 调试用：直接设置固定栏动作（逗号分隔的动作 id），验证编辑态视觉用
        function setQuickBar(ids: string): string {
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
