// fcitx5 通信桥：所有和输入法相关的状态、命令、实时通道都在这里。
//
// 从 InlineKeyboardDaemon 拆出来的（那个文件超过 1300 行，混了通信/路由/窗口/设置
// 四件事）。现在职责很单一：跟 fcitx5 的 addon 说话，把结果整理成属性。
//
// 数据流：
//   addon --socket--> state:{json} / imlist:{json} --> data.js 解析 --> 这里的属性
//   这里 --socket--> key:<keysym>[:<mods>]  --> addon 转 VirtualKeyboardEvent
//   这里 --文件-->  inline-keyboard-expand / -select --> addon 读走即删
//
// 为什么不用文件轮询：轮询最快 40ms（addon 侧）/ 300ms（插件侧），
// socket 推送端到端约 2ms。详见 docs/ARCHITECTURE.md。
import QtQuick
import Quickshell
import Quickshell.Io
import "data.js" as Data

Item {
    id: bridge

    // 非可视组件：Item 才能装子对象（QtObject 没有 default property）
    visible: false
    width: 0
    height: 0

    // 键盘是否打开。由 daemon 同步过来：决定 imlist 兜底轮询要不要跑。
    property bool keyboardOpen: false

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string socketPath: runtimeDir + "/inline-keyboard.sock"
    readonly property string statusPath: runtimeDir + "/inline-keyboard-status.json"
    readonly property string imListPath: runtimeDir + "/inline-keyboard-imlist.json"

    // ---- 面板状态（addon 推送 + 兜底文件读取，两者都过同一套解析）----

    property var candidates: []          // 候选词（空数组 = 没有候选）
    property string preedit: ""          // 拼音串
    property bool panelVisible: false    // addon 报告的可见性（不能叫 visible，Item 内建）
    property bool imKeyboard: false      // 当前输入法是否纯键盘布局（无候选能力）
    property string imName: ""
    property string imLabel: ""          // 子模式标签：rime 中文「万」、英文「abc」、布局「en」
    property string imIcon: ""           // 绝对路径
    property bool hasPrev: false
    property bool hasNext: false
    // 还有没显示的候选。rime 的 bulk 列表没有 pageable，hasNext 恒 false，
    // 这个字段由 addon 另外算（第 19 个候选还取不取得到）。
    property bool hasMore: false

    // 全量候选（候选列表页用）。每项 { i: 原始全局下标, t: 词 }，
    // 带下标是为了让显示层做去重/剔除时不破坏选词准确性。
    property var allCandidates: []

    // 候选内容真的变了才加一。
    //
    // 不能直接监听 candidates：addon 每 40ms 推一次状态、每次都是新数组，
    // 数组替换会触发 onChanged，定时器被无限重启、永远到不了头（踩过）。
    // int 是值类型，只在「数量 / 首项 / 预编辑」真的变了时才 ++。
    property int candRevision: 0

    // ---- 输入法清单 ----

    property var imList: []

    // 每个输入法上一次见到的子模式标签（rime 中文是「万」这种）。
    // 输入法清单里只有它自己的标识（rime 是「ㄓ」），切过去的瞬间
    // addon 还没来得及推子模式，直接用清单值就会先闪一下「ㄓ」再变「万」。
    property var imLabelCache: ({})

    // ---- 诊断 ----
    // socket 是否连着。断开说明 fcitx5 重启了或 addon 没加载。
    readonly property bool socketUp: socket.connected
    // addon 最近一次报告的错误（它会推 error:<kind>:<detail>）。
    // 不认识的指令、内部异常都会走到这里，不再静默丢弃。
    property string lastError: ""

    // fcitx5 当前正在用的 UI 实现名（addon 的 state.ui）。
    // 键盘开着但这个值不等于 selfUi，说明 UI 被 classicui 顶掉了。
    property string currentUi: ""

    // addon 自己的 UI 名（由 addon 在 state 里给出），用来判断 UI 是否被顶掉
    property string selfUi: ""

    // 应用是否已把预编辑渲染进自己的输入框（true 时键盘不再重复显示）
    property bool preeditEmbedded: false

    // 上次 reclaim 的时间戳（ms），用来做 5 秒限流
    property double lastReclaimAt: 0

    // 平铺的「输入法 + 子模式」列表：地球键循环和下拉菜单共用同一份数据。
    // 构造逻辑在 data.js（有单测覆盖 current 唯一性）。
    // 把缓存过的子模式标签补进清单，再交给 buildImRows。
    // 只补键盘型之外的输入法：keyboard-us 的 label 就是「en」，不该被覆盖。
    readonly property var imListForRows: {
        // 不要写 root.*：本文件的 id 是 bridge，root 会解析到外层组件上去，
        // 拿到 undefined（实测报 "Cannot read property 'keyboard-us' of undefined"）
        const cache = bridge.imLabelCache
        const src = bridge.imList
        if (!src || src.length === 0)
            return src
        const out = []
        for (let i = 0; i < src.length; i++) {
            const im = src[i]
            const cached = cache[im.name]
            out.push((im.keyboard || !cached)
                     ? im : Object.assign({}, im, { label: cached }))
        }
        return out
    }

    readonly property var imRows: Data.buildImRows(imListForRows, imName, imLabel)

    // 当前是否英文字模式（按子模式标签是否为纯 ASCII 字母判断）
    readonly property bool isAsciiMode: Data.isAsciiMode(imLabel)

    // ------------------------------------------------------------------

    // 逐项比较两个字符串数组。用来判断 addon 这次推的 items 和上次是不是
    // 真的不一样 —— parseStatus 每次都 JSON.parse 出新数组，哪怕内容相同，
    // 直接赋值也会让下游的 candListModel / 重排全部重跑一遍。
    function sameStrings(a, b) {
        if (a === b)
            return true
        if (!a || !b || a.length !== b.length)
            return false
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i])
                return false
        }
        return true
    }

    function applyStatus(raw) {
        // data.js 的 parseStatus 解析失败时返回上一次的副本，
        // 所以文件半写 / 还没生成的情况不会把候选闪空。
        const st = Data.parseStatus(raw, {
            items: candidates, preedit: preedit,
            visible: panelVisible, keyboard: imKeyboard, im: imName,
            imLabel: imLabel, imIcon: imIcon,
            hasPrev: hasPrev, hasNext: hasNext, hasMore: hasMore,
        })
        const prevLen = candidates.length
        const prevFirst = prevLen > 0 ? String(candidates[0]) : ""
        const prevPre = preedit

        // 只在内容真的变了才赋值。这一句挡住的是「数组对象换了但内容一样」
        // 的推送（打字时很常见：每次按键 addon 都会给一份新 items）。
        const itemsChanged = !sameStrings(candidates, st.items)
        if (itemsChanged)
            candidates = st.items
        if (preedit !== st.preedit)
            preedit = st.preedit
        if (itemsChanged
                || (candidates.length > 0 && String(candidates[0]) !== prevFirst)
                || preedit !== prevPre)
            candRevision++
        panelVisible = st.visible
        imKeyboard = st.keyboard
        imName = st.im
        imLabel = st.imLabel
        imIcon = st.imIcon

        // 记住这个输入法的中文子模式标签，供下次切换时先显示。
        // 同样不能写 root.*（那份是外层组件），否则缓存永远是空的。
        if (st.im !== "" && st.imLabel !== "" && !Data.isAsciiMode(st.imLabel)) {
            if (bridge.imLabelCache[st.im] !== st.imLabel) {
                const next = Object.assign({}, bridge.imLabelCache)
                next[st.im] = st.imLabel
                bridge.imLabelCache = next
            }
        }
        hasPrev = st.hasPrev
        hasNext = st.hasNext
        hasMore = st.hasMore
        currentUi = st.ui
        selfUi = st.self
        preeditEmbedded = st.embedded

        // UI 被 classicui 顶掉时自己抢回来。
        //
        // addon 那边完全按 fcitx5 官方语义走：InputContextFocusOut 会调
        // hideVirtualKeyboard()，它就把 shown_ 置 false 并把 UI 交还 classicui。
        // 但失焦不等于用户收起键盘（截图、切窗口都会失焦），键盘是否真的
        // 还开着只有插件知道，所以「要不要抢回来」在这里判断。
        //
        // 限流 5 秒：reclaim 会触发 setInputMethodMode -> updateAvailability，
        // 本身又会发一次 UIChanged，不限流会绕着回调链打转。
        if (bridge.keyboardOpen && st.ui !== "" && st.self !== ""
                && st.ui !== st.self) {
            const nowMs = Date.now()
            if (nowMs - bridge.lastReclaimAt >= 5000) {
                bridge.lastReclaimAt = nowMs
                console.error("[inline-keyboard/fcitx] ui=" + st.ui + " 不是自己，reclaim")
                sendFcitx("reclaim")
            }
        }
    }

    function applyImList(raw) {
        imList = Data.parseImList(raw, imList)
    }

    function handleSocketData(data) {
        // SplitParser 已按 \n 切好一条完整消息，这里不能再找 \n。
        const line = String(data || "")
        if (line.startsWith("state:")) {
            applyStatus(line.substring(6))
        } else if (line.startsWith("imlist:")) {
            applyImList(line.substring(7))
        } else if (line.startsWith("allcand:")) {
            try {
                const arr = JSON.parse(line.substring(8))
                if (Array.isArray(arr)) {
                    // 新格式 [{i,t}]；旧 addon 给纯字符串数组，补上下标
                    allCandidates = arr.map((x, n) => (x && typeof x === "object")
                        ? x : { i: n, t: String(x == null ? "" : x) })
                }
            } catch (e) {
                console.error("[inline-keyboard/fcitx] 全量候选解析失败: " + e)
            }
        } else if (line.startsWith("error:")) {
            lastError = line.substring(6)
            // addon 不认 text:（还没升级）→ 以后直接走剪贴板
            if (lastError.indexOf("unknown-command:text") === 0)
                textSupported = false
            console.error("[inline-keyboard/fcitx] addon 报告: " + lastError)
        }
    }

    // ---- 发命令 ----

    // 发一行到 addon。没连上返回 false，调用方据此回退 ydotool。
    function sendFcitx(line) {
        if (!socket.connected)
            return false
        socket.write(line + "\n")
        return true
    }

    // ---- 文本提交（表情 / 符号页）----
    // 为什么不用按键通道：一个表情是多个码位，key: 是 keysym 语义，
    // ydotool 也只认键码 —— 只有 InputContext::commitString 送得进去。
    // 老版本 addon 不认识 text: 会回 error:unknown-command:text…，
    // 收到就把 textSupported 关掉，之后直接走剪贴板，不再白发一次。
    property bool textSupported: true

    function commitText(text) {
        if (!text || !textSupported || !socket.connected)
            return false
        socket.write("text:" + text + "\n")
        return true
    }

    // 兜底：复制到剪贴板，由用户自己粘贴。
    // wl-clipboard 没装就别假装复制成功了 —— 平板上真出现过这种情况（toast 说已复制，实际什么都没发生）
    property bool clipboardAvailable: false

    function copyText(text) {
        if (!text || !clipboardAvailable)
            return false
        clipboardProc.command = ["wl-copy", text]
        clipboardProc.running = true
        return true
    }

    // 向 addon 要全量候选。addon 用 BulkCandidateList::candidateFromAll
    // 一次取完，直接推 allcand:[{i,t}...]，不写文件也不轮询。
    function requestAllCandidates() {
        return sendFcitx("expand")
    }

    // 选第 N 个候选。index 是 addon 的 candidateFromAll 全局下标。
    // 走 socket 的 select: 命令——addon 重写后不再读 inline-keyboard-select 文件，
    // 之前写文件的做法会让选词静默失效（点了没反应，也不报错）。
    function selectCandidate(index) {
        if (index < 0)
            return false
        return sendFcitx("select:" + index)
    }

    // ------------------------------------------------------------------

    Socket {
        id: socket
        path: bridge.socketPath

        // Quickshell 的 Socket 只暴露 connected，没有 onDisconnected /
        // onSocketError 可接（查 qmltypes 确认：这两个是 C++ 侧槽名，QML 里
        // 写上去会直接 "Cannot assign to non-existent property"，整个
        // FcitxBridge 加载失败、插件变 disabled）。所以掉线只能靠
        // connected 属性变化 + 重连 Timer 兜，别指望事件通知。

        // DataStream 不设 parser 就永远不会触发 read —— 连上了也收不到字节。
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => bridge.handleSocketData(data)
        }
    }

    // connected 是开关，初始 false 且不会自动连；断线（fcitx5 重启）也靠它重连。
    Timer {
        interval: 1000
        // 只有键盘打开时才连。
        // 无条件 running: true 会让插件在键盘收起后仍每秒重连，
        // 一直占着 addon 的唯一客户端槽位 —— 任何别的客户端
        // （scripts/test-addon.py、排障工具）刚连上就被顶掉。
        running: keyboardOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!socket.connected)
                socket.connected = true
        }
    }

    // 键盘收起就把连接还回去，别赖着。
    //
    // 打开这一侧不用做任何事：addon 在 acceptClient 里就把 shown_ 置 true
    // 并切到 OnScreenKeyboard 了（socket 连上 = 键盘开了，这是它唯一的
    // 开关信号）。这里如果也发 mode:osk，会和 addon 内部的
    // setInputMethodMode -> hide/showVirtualKeyboard 回调链撞在一起。
    onKeyboardOpenChanged: {
        if (!keyboardOpen && socket.connected)
            socket.connected = false
    }

    // 剪贴板兜底：wl-copy 直接吃文本参数，不经过 shell，省掉转义问题
    Process {
        id: clipboardProc
        command: ["true"]
    }

    // 开局探一次有没有 wl-copy（Wayland 下唯一的复制手段）
    Process {
        id: clipboardProbe
        command: ["sh", "-c", "command -v wl-copy >/dev/null && echo yes || echo no"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: bridge.clipboardAvailable =
                                  String(text || "").trim() === "yes"
        }
    }

    // socket 没连上时（fcitx5 没起 / addon 没加载）退回文件读取兜底
    Process {
        id: statusRead
        command: ["sh", "-c", "cat \"" + bridge.statusPath + "\" 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: bridge.applyStatus(text)
        }
    }

    Process {
        id: imListRead
        command: ["sh", "-c", "cat \"" + bridge.imListPath + "\" 2>/dev/null"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: bridge.applyImList(text)
        }
    }

    Timer {
        interval: 3000
        running: bridge.keyboardOpen && !socket.connected
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!imListRead.running)
                imListRead.running = true
            if (!statusRead.running)
                statusRead.running = true
        }
    }

}
