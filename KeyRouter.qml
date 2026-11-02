// 按键路由：修饰键状态机 + 注入。只回答「发给 fcitx5 还是交给合成器」。
//   组合键必须走 ydotool：socket 到不了合成器；且要优先于输入法，否则 Ctrl+C 要按两次
import QtQuick
import Quickshell
import Quickshell.Io
import "data.js" as Data
import "keyroute.js" as KeyRoute
import "modifiers.js" as Modifiers
import qs.Common
import qs.Services

Item {
    id: router

    // fcitx5 桥（由 daemon 注入）。直通要靠它发按键、读当前输入法类型。
    property var bridge: null
    // Ctrl+Alt+F1..F12 会被内核当成 VT 切换，虚拟键盘上误触就是整个桌面跳走
    property bool blockTtySwitch: true
    // 键盘是否开着。关着的时候没必要每 3 秒起一次 sh 去探 ydotoold。
    property bool active: false
    // 当前动作表（自定义动作要拿 cmd）
    property var actions: []
    // 修饰键状态在窗口销毁后仍要保留，所以存在 daemon 的生命周期对象上
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
        "shift": shiftState,
        "caps": capsState,
        "ctrl": ctrlState,
        "alt": altState,
        "super": superState,
        "fn": fnState,
        "page": pageState
    })
    // 组合键（Ctrl/Alt/Super）要优先于输入法：预编辑挂着时 fcitx5 会先把组合键交给输入法引擎判断，结果不可控，所以组合键一律走 ydotool。
    readonly property bool hasComboModifier: ctrlState !== 0 || altState !== 0 || superState !== 0
    // 唯一后端。它通过 uinput 造真实键盘设备，事件走 libinput → 合成器第一环，比注入按键事件更底层。
    // 未探测过时先试着注入，探到不通才拒；否则刚开键盘那一下会全被吞掉
    property var ydotooldUp: undefined
    // ydotool 一次只能跑一条，连按要排队
    property var pendingCommands: []
    property double lastToastAt: 0
    // ydotoold 探到 down 后按 3 秒节流重探，避免一次误判把整场按键锁死
    property double lastProbeAt: 0
    // 测试用：只记录「会发什么」，不真的注入（不调 ydotool、不发 socket）。
    // 由 debugSetDryRun / debugInjected 驱动，见 scripts/acceptance.py。
    property bool dryRun: false
    property var dryRunLog: []

    function noteDryRun(code, sym, kind, route, mods) {
        const log = dryRunLog.slice();
        log.push({
            "code": code,
            "sym": sym || "",
            "kind": kind || "",
            "route": route,
            "mods": mods
        });
        while (log.length > 50)log.shift()
        dryRunLog = log;
    }

    function stateOf(name) {
        switch (name) {
        case "shift":
            return shiftState;
        case "caps":
            return capsState;
        case "ctrl":
            return ctrlState;
        case "alt":
            return altState;
        case "super":
            return superState;
        case "fn":
            return fnState;
        case "page":
            return pageState;
        }
        return 0;
    }

    function setState(name, value) {
        switch (name) {
        case "shift":
            shiftState = value;
            return ;
        case "caps":
            capsState = value;
            return ;
        case "ctrl":
            ctrlState = value;
            return ;
        case "alt":
            altState = value;
            return ;
        case "super":
            superState = value;
            return ;
        case "fn":
            fnState = value;
            return ;
        case "page":
            pageState = value;
            return ;
        }
    }

    // 点一次修饰键：具体流转由 modifiers.js 按切换方式决定
    function cycleModifier(name) {
        const now = Date.now();
        const sameKey = lastModifierTapped === name;
        setState(name, Modifiers.nextModifierState({
            "name": name,
            "current": stateOf(name),
            "mode": modifierMode,
            "isSameKey": sameKey,
            "sinceLastTapMs": sameKey ? now - lastModifierTapAt : -1,
            "doubleTapMs": doubleTapInterval
        }));
        lastModifierTapped = name;
        lastModifierTapAt = now;
    }

    // 改切换方式时把残留状态清掉，避免「切到不锁定模式却还锁着」
    function clearAllModifiers() {
        shiftState = 0;
        capsState = 0;
        ctrlState = 0;
        altState = 0;
        superState = 0;
        fnState = 0;
        pageState = 0;
        lastModifierTapped = "";
        lastModifierTapAt = 0;
    }

    // 修饰键按下 / 松开：只有「按住才生效」（noLock）会用到
    function modifierPress(keyData) {
        const name = Modifiers.modifierNameFor(keyData);
        if (name === "")
            return ;

        setState(name, Modifiers.pressModifierState(modifierMode, stateOf(name), name));
    }

    function modifierRelease(keyData) {
        const name = Modifiers.modifierNameFor(keyData);
        if (name === "")
            return ;

        setState(name, Modifiers.releaseModifierState(modifierMode, stateOf(name), name));
    }

    // 普通键按下后：软激活(1)清零，锁定(2)与 caps lock 保留
    // Caps 的真值在系统那边，本地这份只是镜像。两条来源：
    //   1. DMS 的 evdev 服务（装了就实时推，我们自己发 58 也会绕回来）
    //   2. 读指示灯（evdev 没装时用它兜底，读不到的设备——比如没有指示灯的平板——保持本地状态）
    function syncSystemCaps() {
        // 2 才是「锁定」（背景高亮）；1 是一次性，会被画成描边
        if (typeof DMSService !== "undefined" && DMSService && DMSService.capsLockState)
            router.capsState = 2;
        else if (!capsProbe.running)
            capsProbe.running = true;
    }

    // 兼容旧调用点
    function readSystemCaps() {
        syncSystemCaps();
    }

    function clearTransientModifiers() {
        const next = Modifiers.clearTransient(modifierStates);
        shiftState = next.shift;
        capsState = next.caps;
        ctrlState = next.ctrl;
        altState = next.alt;
        superState = next.super;
        fnState = next.fn || 0;
        pageState = next.page || 0;
    }

    // 调试用：状态打成一串，方便 IPC 自测
    function stateSummary() {
        return "shift=" + shiftState + " caps=" + capsState + " ctrl=" + ctrlState + " alt=" + altState + " super=" + superState + " fn=" + fnState + " page=" + pageState;
    }

    function handleKey(keyData) {
        if (!keyData)
            return ;

        const k = keyData.k;
        if (k === "stub") {
            notifyUnimplemented();
            return ;
        }
        // 内核级的 VT 切换拦不住，只能不发
        const label = keyData.fn && keyData.fn.l ? keyData.fn.l : (keyData.l || "");
        if (router.blockTtySwitch && Modifiers.isTtySwitchCombo(label, ctrlState, altState, shiftState))
            return ;

        const modifier = Modifiers.modifierNameFor(keyData);
        if (modifier !== "") {
            cycleModifier(modifier);
            // Caps 是系统的锁定键：本地翻完还要把真键发出去，系统并不知道我们这份状态
            if (modifier === "caps")
                injectKey(58, "Caps Lock", "key", false);

            return ;
        }
        if (k === "space")
            injectKey(57, "space", k);
        else
            injectKey(keyData.c, keyData.l, keyData.k, keyData.shifted === true);
        // 一次性修饰键用完复位（锁定态保留）
        clearTransientModifiers();
    }

    // 注入一个键：修饰键状态包成按下/松开序列，一次 ydotool 调用发完。
    // sym 是布局里的键名（"a" / "Backspace" / "Enter"…），用于走 socket 直通。
    function injectKey(code, sym, kind, shifted) {
        if (!code)
            return ;

        const b = bridge;
        let route = KeyRoute.ROUTE.ydotool;
        let mods = 0;
        if (sym) {
            // 交给输入法还是直接发真键：判据在 keyroute.js（纯函数，有单测）。
            // 控制键交给输入法会被 fcitx 吞掉（Wayland 上不转发给应用），必须发真键。
            route = KeyRoute.decideRoute(sym, kind, {
                "available": b !== null && b !== undefined,
                "preedit": b ? b.preedit : "",
                "imKeyboard": b ? b.imKeyboard : false,
                "isAsciiMode": b ? b.isAsciiMode : false,
                "combo": hasComboModifier
            });
            // sym 本身已经是移位后的符号时不能再叠 Shift，否则 / → ? 会变成 ? 再移位
            // key:<sym>[:<mods>] 里冒号是分隔符：sym 本身是 : 会被 addon 截成空串（最后变成空格）
            if (route === KeyRoute.ROUTE.fcitx && sym.indexOf(":") >= 0)
                route = KeyRoute.ROUTE.ydotool;

            if (route === KeyRoute.ROUTE.fcitx)
                mods = (shiftState && !shifted) ? 1 : 0;

        }
        // 测试用：只记下要发什么，不真的往系统发
        if (dryRun) {
            noteDryRun(code, sym, kind, route, mods);
            return ;
        }
        if (sym && route === KeyRoute.ROUTE.fcitx) {
            if (b && b.sendFcitx("key:" + sym + (mods ? ":" + mods : ""))) {
                clearTransientModifiers();
                return ;
            }
        }
        if (ydotooldUp === false) {
            // 不锁死：ydotoold 可能刚起来，节流重探，探到 up 立刻恢复
            const now = Date.now();
            if (now - router.lastProbeAt > 3000) {
                router.lastProbeAt = now;
                router.probeYdotoold();
            }
            notifyUnimplemented("ydotoold is not running");
            return ;
        }
        const seq = Modifiers.modifierSequence(modifierStates);
        const cmd = ["ydotool", "key"];
        for (let i = 0; i < seq.down.length; i++) cmd.push(seq.down[i])
        cmd.push(code + ":1");
        cmd.push(code + ":0");
        for (let i = 0; i < seq.up.length; i++) cmd.push(seq.up[i])
        runCommand(cmd);
    }

    function notifyUnimplemented() {
        if (typeof ToastService === "undefined" || !ToastService)
            return ;

        // 长按重复时每 60ms 一次，没有节流会刷满屏幕
        const now = Date.now();
        if (now - router.lastToastAt < 3000)
            return ;

        router.lastToastAt = now;
        ToastService.showInfo(I18n.trFor("inlineKeyboard", "ydotoold is not running"));
    }

    function findAction(key) {
        const list = actions || [];
        for (let i = 0; i < list.length; i++) {
            const a = list[i];
            if (a.id === key || a.label === key)
                return a;

        }
        return null;
    }

    function runCommand(cmd) {
        if (ydotoolProc.running) {
            // 丢最新的一条而不是最早的：旧的已经在路上，删掉最早那条会让先敲的字消失、后面的照常出现
            if (router.pendingCommands.length >= 32) {
                console.warn("inlineKeyboard: 按键队列已满，丢弃最新一条");
                return ;
            }
            // 必须写 router：root 会解析到外层 daemon 的队列，键会排错队甚至注进别的窗口
            router.pendingCommands.push(cmd);
            return ;
        }
        ydotoolProc.command = cmd;
        ydotoolProc.running = true;
    }

    function probeYdotoold() {
        // 有的发行版把 ydotoold 跑成系统服务，socket 不在 XDG_RUNTIME_DIR 下
        ydotooldProbe.command = ["sh", "-c", 'pgrep -x ydotoold >/dev/null && test -S "${YDOTOOL_SOCKET:-$XDG_RUNTIME_DIR/.ydotool_socket}" && echo up || echo down'];
        ydotooldProbe.running = true;
    }

    // 非可视组件：Item 才能装子对象（QtObject 没有 default property）
    visible: false
    width: 0
    height: 0
    // 打开键盘时探一次；之后只在注入失败时重探
    onActiveChanged: {
        if (active)
            router.probeYdotoold();

    }

    Process {
        id: capsProbe

        command: ["sh", "-c", "cat /sys/class/leds/*::capslock/brightness 2>/dev/null | head -1"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw === "")
                    return ;

                const v = parseInt(raw, 10);
                if (!isNaN(v))
                    router.capsState = v > 0 ? 2 : 0;

            }
        }

    }

    Connections {
        function onCapsLockStateChanged() {
            router.syncSystemCaps();
        }

        target: typeof DMSService !== "undefined" ? DMSService : null
    }

    Process {
        id: ydotoolProc

        command: ["true"]
        // 注入失败才重探（ydotoold 掉了 / socket 没了）。成功时什么都不做，键盘开着也不会有定时进程。
        onExited: (exitCode) => {
            if (exitCode !== 0)
                router.probeYdotoold();
            else
                router.ydotooldUp = true;
            // 队列里还有就接着跑
            if (router.pendingCommands.length > 0) {
                ydotoolProc.command = router.pendingCommands.shift();
                ydotoolProc.running = true;
            }
        }
    }

    Process {
        id: ydotooldProbe

        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                router.ydotooldUp = String(text || "").trim() === "up";
            }
        }

    }

}
