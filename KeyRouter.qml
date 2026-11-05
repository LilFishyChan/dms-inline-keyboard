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
    // 触控板后端的 socket（由 daemon 注入）。修饰键要同步到那个真实的键盘设备上。
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

    // 状态变化 → 同步到真实的键盘设备。
    // 修饰键在系统里必须是「按住不放」的：只有这样，触控板的点击、拖动，
    // 以及任何应用看到的 key state 才和物理键盘一致。
    // 只在「按下 ↔ 松开」的那一刻发事件；值 1↔2 之间（一次性转锁定）不发，
    // 否则会重复按下、松开时只发一次 up，修饰键就卡住了。
    function syncModifierKey(name, prev, next) {
        const code = Modifiers.MODIFIER_KEYCODES[name];
        if (!code)
            return ;

        const wasDown = prev > 0;
        const isDown = next > 0;
        if (wasDown === isDown)
            return ;

        // 修饰键和普通键走同一条 ydotool 路径，不再经过触控板后端
        router.runKey(code, isDown ? 1 : 0);
    }

    // 收起键盘时用：把修饰键全部松开。
    // 必须走 setState —— 直接赋值不会触发 syncModifierKey，系统里就会一直卡着
    // 一个按住的 Super，之后所有点击都变成 Super+Click，直到注销。
    // caps 不收：它是锁存状态，和「按住」不是一回事。
    function releaseAllModifiers() {
        const names = ["shift", "ctrl", "alt", "super"];
        for (let i = 0; i < names.length; i++) {
            if (router.stateOf(names[i]) > 0)
                router.setState(names[i], 0);

        }
    }

    // 收起 / 最小化时把「按着」的普通键也松开。
    // 只松修饰键不够：按住 Backspace（或任意键）时点收起，up 永远发不出去，
    // 系统里那个键会一直是按下态、一直 auto-repeat。
    function releaseAllKeys() {
        const keys = Object.keys(router.heldKeys);
        for (let i = 0; i < keys.length; i++) {
            const how = router.heldKeys[keys[i]];
            if (how === KeyRoute.ROUTE.fcitx || how === "fallback")
                continue;

            router.runKey(Number(keys[i]), 0);
        }
        router.heldKeys = {};
    }

    function setState(name, value) {
        const prev = router.stateOf(name);
        switch (name) {
        case "shift":
            shiftState = value;
            break;
        case "caps":
            capsState = value;
            break;
        case "ctrl":
            ctrlState = value;
            break;
        case "alt":
            altState = value;
            break;
        case "super":
            superState = value;
            break;
        case "fn":
            fnState = value;
            break;
        case "page":
            pageState = value;
            break;
        }
        router.syncModifierKey(name, prev, value);
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

    // 改切换方式时把残留状态清掉，避免「切到不锁定模式却还锁着」。
    // 必须走 setState：直接赋值不会触发 syncModifierKey，系统里的修饰键就会一直按着。
    function clearAllModifiers() {
        const names = ["shift", "caps", "ctrl", "alt", "super", "fn", "page"];
        for (let i = 0; i < names.length; i++) {
            if (router.stateOf(names[i]) !== 0)
                router.setState(names[i], 0);

        }
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
        // 同样必须走 setState —— 这里是把「一次性」修饰键从 1 变 0 的地方，
        // 直接赋值的话系统里那个修饰键永远不会松开，之后所有点击都带着它。
        const next = Modifiers.clearTransient(modifierStates);
        const names = ["shift", "caps", "ctrl", "alt", "super", "fn", "page"];
        for (let i = 0; i < names.length; i++) {
            const n = names[i];
            const want = next[n] || 0;
            if (router.stateOf(n) !== want)
                router.setState(n, want);

        }
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

    // 按下的普通键：code → 路由（fcitx / 注入）。松开时按这份记录决定要不要补 up。
    property var heldKeys: ({})

    // 决定一个键走输入法还是走真实按键。抽出来是因为按下和松开各要问一次。
    function routeFor(sym, kind) {
        const b = router.bridge;
        if (!sym)
            return KeyRoute.ROUTE.ydotool;

        let route = KeyRoute.decideRoute(sym, kind, {
            "available": b !== null && b !== undefined,
            "preedit": b ? b.preedit : "",
            "imKeyboard": b ? b.imKeyboard : false,
            "isAsciiMode": b ? b.isAsciiMode : false,
            "combo": router.hasComboModifier
        });
        // key:<sym>[:<mods>] 里冒号是分隔符：sym 本身是 : 会被 addon 截成空串
        if (route === KeyRoute.ROUTE.fcitx && sym.indexOf(":") >= 0)
            route = KeyRoute.ROUTE.ydotool;

        return route;
    }

    // 按下发 down，松开发 up —— 和真实键盘同构。
    // 长按重复交给系统（内核的 auto-repeat），不再自己定时间隔重发。
    // 修饰键此时已经真实按在键盘设备上了，所以 down 不带修饰键序列。
    function keyDown(keyData) {
        if (!keyData)
            return ;

        const k = keyData.k;
        if (k === "stub") {
            router.notifyUnimplemented();
            return ;
        }
        // 内核级的 VT 切换拦不住，只能不发
        const label = keyData.fn && keyData.fn.l ? keyData.fn.l : (keyData.l || "");
        if (router.blockTtySwitch && Modifiers.isTtySwitchCombo(label, ctrlState, altState, shiftState))
            return ;

        const code = k === "space" ? 57 : keyData.c;
        if (!code)
            return ;

        const sym = k === "space" ? "space" : keyData.l;
        let route = router.routeFor(sym, k);

        if (route === KeyRoute.ROUTE.fcitx) {
            const mods = (shiftState && keyData.shifted !== true) ? 1 : 0;
            if (router.bridge && router.bridge.sendFcitx("key:" + sym + (mods ? ":" + mods : ""))) {
                router.heldKeys[code] = KeyRoute.ROUTE.fcitx;
                return ;
            }
            // 输入法没接上就回落注入
            route = KeyRoute.ROUTE.ydotool;
        }

        // 测试用：只记下要发什么，不真的往系统发（与 injectKey 的 dryRun 行为一致）
        if (dryRun) {
            router.noteDryRun(code, sym, k, KeyRoute.ROUTE.ydotool, 0);
            return ;
        }

        // 按键注入只走 ydotool：down / up 分开发，按住才成立
        // （长按连删、Shift+字母靠这个；触控板 helper 只管指针，不掺和键盘）
        router.heldKeys[code] = KeyRoute.ROUTE.ydotool;
        router.runKey(code, 1);
    }

    // 单个按键的按下 / 松开。走 ydotool 的 code:state 形式：
    //   29:1 按下、29:0 松开（ydotool 没有独立 keydown/keyup 子命令）
    function runKey(code, down) {
        if (!code)
            return ;

        // dry-run 只在注入口拦，不记录。记录交给 keyDown 统一做一次：
        // 这里再记的话一次按键会产生 down/up 两条，验收里 n1 == 1 的断言会挂
        if (router.dryRun)
            return ;

        if (ydotooldUp === false) {
            // 不锁死：ydotoold 可能刚起来，节流重探，探到 up 立刻恢复
            const now = Date.now();
            if (now - router.lastProbeAt > 3000) {
                router.lastProbeAt = now;
                router.probeYdotoold();
            }
            router.notifyUnimplemented("ydotoold is not running");
            return ;
        }
        router.runCommand(["ydotool", "key", code + ":" + (down ? 1 : 0)]);
    }

    function keyUp(keyData) {
        if (!keyData)
            return ;

        const k = keyData.k;
        const code = k === "space" ? 57 : keyData.c;
        if (!code)
            return ;

        const how = router.heldKeys[code];
        delete router.heldKeys[code];

        if (how === KeyRoute.ROUTE.fcitx || how === "fallback") {
            // 一次性修饰键在松开之后复位。fcitx 路径也必须走这一步：
            // 中文模式下普通字母默认走 fcitx，漏掉就会让 Shift 一直卡着
            router.clearTransientModifiers();
            return ;
        }

        router.runKey(code, 0);

        // 一次性修饰键在**松开之后**才复位：按下那一刻复位的话，
        // 这次按键的 down 就已经没有修饰键了，Shift+a 会变成 a。
        router.clearTransientModifiers();
    }

    // 长按重复：只对「走输入法直通」的键有意义。
    // 走真键那条路的键是按着不放的，auto-repeat 由系统产生；
    // 而 fcitx 的 key: 消息是一次性的，退格/Del 要连续删只能自己定时重发。
    function keyRepeat(keyData) {
        if (!keyData)
            return ;

        const k = keyData.k;
        const code = k === "space" ? 57 : keyData.c;
        if (!code)
            return ;

        // 没在按着、或者这个键走的是真键路径 —— 都不用我们管
        if (router.heldKeys[code] !== KeyRoute.ROUTE.fcitx)
            return ;

        const sym = k === "space" ? "space" : keyData.l;
        const mods = (shiftState && keyData.shifted !== true) ? 1 : 0;
        if (router.bridge)
            router.bridge.sendFcitx("key:" + sym + (mods ? ":" + mods : ""));

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
        // 修饰键已经由 syncModifierKey 真按真松，这里不再拼 modifierSequence：
        // 再拼一遍会按两次、末尾多松一次，系统里松了而 UI 还显示锁定
        runCommand(["ydotool", "key", code + ":1", code + ":0"]);
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
