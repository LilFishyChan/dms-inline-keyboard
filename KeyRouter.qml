// 按键路由：修饰键状态机 + 注入。只回答「发给 fcitx5 还是交给合成器」。
//   组合键必须走 ydotool：socket 到不了合成器；且要优先于输入法，否则 Ctrl+C 要按两次
import QtQuick
import Quickshell
import Quickshell.Io
import "data.js" as Data
import "modifiers.js" as Modifiers
import "keyroute.js" as KeyRoute

Item {
    id: router

    // 非可视组件：Item 才能装子对象（QtObject 没有 default property）
    visible: false
    width: 0
    height: 0

    // fcitx5 桥（由 daemon 注入）。直通要靠它发按键、读当前输入法类型。
    property var bridge: null
    // 键盘是否开着。关着的时候没必要每 3 秒起一次 sh 去探 ydotoold。
    property bool active: false
    // 当前动作表（自定义动作要拿 cmd）
    property var actions: []

    // ---- 修饰键状态（窗口销毁后仍然保留，所以放在 daemon 生命周期对象上）----
    // 0 = 未激活 / 1 = 一次性（下一个普通键后复位）/ 2 = 锁定
    property int shiftState: 0
    property int capsState: 0
    property int ctrlState: 0
    property int altState: 0
    property int superState: 0
    property int fnState: 0
    // 页面键状态：0 = 第一页 / 1 = 一次性 / 2 = 锁定（第二页）
    property int pageState: 0

    // 切换方式：noLock / toggle / tapLock / doubleTapLock（设置页可选）
    property string modifierMode: "doubleTapLock"
    readonly property int doubleTapInterval: Modifiers.DEFAULT_DOUBLE_TAP_MS
    property double lastModifierTapAt: 0
    property string lastModifierTapped: ""

    // 给卡片的快照：每次状态变化都生成新对象，键盘才收得到通知
    readonly property var modifierStates: ({
        shift: shiftState, caps: capsState, ctrl: ctrlState,
        alt: altState, super: superState, fn: fnState, page: pageState
    })

    // 组合键（Ctrl/Alt/Super）要优先于输入法：
    // 预编辑挂着时 fcitx5 会先把组合键交给输入法引擎判断，
    readonly property bool hasComboModifier: ctrlState !== 0 || altState !== 0 || superState !== 0

    // ---- ydotool ----
    // 唯一后端。它通过 uinput 造真实键盘设备，事件走 libinput → 合成器第一环，
    property bool ydotooldUp: false

    // 测试用：只记录「会发什么」，不真的注入（不调 ydotool、不发 socket）。
    // 由 debugSetDryRun / debugInjected 驱动，见 scripts/acceptance.py。
    property bool dryRun: false
    property var dryRunLog: []

    function noteDryRun(code, sym, kind, route, mods) {
        const log = dryRunLog.slice()
        log.push({
            code: code,
            sym: sym || "",
            kind: kind || "",
            route: route,
            mods: mods
        })
        while (log.length > 50)
            log.shift()
        dryRunLog = log
    }

    // ---- 修饰键 ----

    function stateOf(name) {
        switch (name) {
        case "shift": return shiftState
        case "caps": return capsState
        case "ctrl": return ctrlState
        case "alt": return altState
        case "super": return superState
        case "fn": return fnState
        case "page": return pageState
        }
        return 0
    }

    function setState(name, value) {
        switch (name) {
        case "shift": shiftState = value; return
        case "caps": capsState = value; return
        case "ctrl": ctrlState = value; return
        case "alt": altState = value; return
        case "super": superState = value; return
        case "fn": fnState = value; return
        case "page": pageState = value; return
        }
    }

    // 点一次修饰键：具体流转由 modifiers.js 按切换方式决定
    function cycleModifier(name) {
        const now = Date.now()
        const sameKey = lastModifierTapped === name
        setState(name, Modifiers.nextModifierState({
            name: name,
            current: stateOf(name),
            mode: modifierMode,
            isSameKey: sameKey,
            sinceLastTapMs: sameKey ? now - lastModifierTapAt : -1,
            doubleTapMs: doubleTapInterval
        }))
        lastModifierTapped = name
        lastModifierTapAt = now
    }

    // 改切换方式时把残留状态清掉，避免「切到不锁定模式却还锁着」
    function clearAllModifiers() {
        shiftState = 0
        capsState = 0
        ctrlState = 0
        altState = 0
        superState = 0
        fnState = 0
        pageState = 0
        lastModifierTapped = ""
        lastModifierTapAt = 0
    }

    // 修饰键按下 / 松开：只有「按住才生效」（noLock）会用到
    function modifierPress(keyData) {
        const name = Modifiers.modifierNameFor(keyData)
        if (name === "")
            return
        setState(name, Modifiers.pressModifierState(modifierMode, stateOf(name), name))
    }

    function modifierRelease(keyData) {
        const name = Modifiers.modifierNameFor(keyData)
        if (name === "")
            return
        setState(name, Modifiers.releaseModifierState(modifierMode, stateOf(name), name))
    }

    // 普通键按下后：软激活(1)清零，锁定(2)与 caps lock 保留
    function clearTransientModifiers() {
        const next = Modifiers.clearTransient(modifierStates)
        shiftState = next.shift
        capsState = next.caps
        ctrlState = next.ctrl
        altState = next.alt
        superState = next.super
        fnState = next.fn || 0
        pageState = next.page || 0
    }

    // 调试用：状态打成一串，方便 IPC 自测
    function stateSummary() {
        return "shift=" + shiftState + " caps=" + capsState
             + " ctrl=" + ctrlState + " alt=" + altState + " super=" + superState
             + " fn=" + fnState + " page=" + pageState
    }

    // ---- 按键分发 ----

    function handleKey(keyData) {
        if (!keyData)
            return
        const k = keyData.k
        if (k === "stub") {
            notifyUnimplemented("This key")
            return
        }
        const modifier = Modifiers.modifierNameFor(keyData)
        if (modifier !== "") {
            cycleModifier(modifier)
            return
        }
        if (k === "space")
            injectKey(57, "space")     // 布局里没有码，keysym 名单独给
        else
            injectKey(keyData.c, keyData.l, keyData.k)
        // 一次性修饰键用完复位（锁定态保留）
        clearTransientModifiers()
    }

    // 注入一个键：修饰键状态包成按下/松开序列，一次 ydotool 调用发完。
    // sym 是布局里的键名（"a" / "Backspace" / "Enter"…），用于走 socket 直通。
    function injectKey(code, sym, kind) {
        if (!code)
            return
        const b = bridge
        let route = KeyRoute.ROUTE.ydotool
        let mods = 0
        if (sym) {
            // 交给输入法还是直接发真键：判据在 keyroute.js（纯函数，有单测）。
            // 控制键交给输入法会被 fcitx 吞掉（Wayland 上不转发给应用），必须发真键。
            route = KeyRoute.decideRoute(sym, kind, {
                available: b !== null && b !== undefined,
                preedit: b ? b.preedit : "",
                imKeyboard: b ? b.imKeyboard : false,
                isAsciiMode: b ? b.isAsciiMode : false,
                combo: hasComboModifier
            })
            if (route === KeyRoute.ROUTE.fcitx)
                mods = shiftState ? 1 : 0
        }
        // 测试用：只记下要发什么，不真的往系统发
        if (dryRun) {
            noteDryRun(code, sym, kind, route, mods)
            return
        }
        if (sym && route === KeyRoute.ROUTE.fcitx) {
            if (b && b.sendFcitx("key:" + sym + (mods ? ":" + mods : ""))) {
                clearTransientModifiers()
                return
            }
        }
        if (!ydotooldUp) {
            notifyUnimplemented("ydotoold is not running")
            return
        }
        const seq = Modifiers.modifierSequence(modifierStates)
        const cmd = ["ydotool", "key"]
        for (let i = 0; i < seq.down.length; i++)
            cmd.push(seq.down[i])
        cmd.push(code + ":1")
        cmd.push(code + ":0")
        for (let i = 0; i < seq.up.length; i++)
            cmd.push(seq.up[i])
        runCommand(cmd)
    }

    // ---- 工具 ----

    function notifyUnimplemented(label) {
        if (typeof ToastService === "undefined" || !ToastService)
            return
        const term = label + " is not implemented yet"
        ToastService.showInfo((typeof I18n !== "undefined" && I18n && I18n.trFor)
                              ? I18n.trFor("inlineKeyboard", term) : term)
    }

    function findAction(key) {
        const list = actions || []
        for (let i = 0; i < list.length; i++) {
            const a = list[i]
            if (a.id === key || a.label === key)
                return a
        }
        return null
    }


    Process {
        id: ydotoolProc
        command: ["true"]
        // 注入失败才重探（ydotoold 掉了 / socket 没了）。成功时什么都不做，
        // 键盘开着也不会有定时进程。
        onExited: exitCode => { if (exitCode !== 0) router.probeYdotoold() }
    }

    function runCommand(cmd) {
        ydotoolProc.command = cmd
        ydotoolProc.running = true
    }

    Process {
        id: ydotooldProbe
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                router.ydotooldUp = String(text || "").trim() === "up"
            }
        }
    }

    function probeYdotoold() {
        ydotooldProbe.command = ["sh", "-c",
            'pgrep -x ydotoold >/dev/null && test -S "$XDG_RUNTIME_DIR/.ydotool_socket" && echo up || echo down']
        ydotooldProbe.running = true
    }

    // 打开键盘时探一次；之后只在注入失败时重探
    onActiveChanged: if (active) router.probeYdotoold()
}
