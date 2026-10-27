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

    // ---- 输入法清单 ----

    property var imList: []

    // ---- 诊断 ----
    // socket 是否连着。断开说明 fcitx5 重启了或 addon 没加载。
    readonly property bool socketUp: socket.connected
    // addon 最近一次报告的错误（它会推 error:<kind>:<detail>）。
    // 不认识的指令、内部异常都会走到这里，不再静默丢弃。
    property string lastError: ""

    // 平铺的「输入法 + 子模式」列表：地球键循环和下拉菜单共用同一份数据。
    // 构造逻辑在 data.js（有单测覆盖 current 唯一性）。
    readonly property var imRows: Data.buildImRows(imList, imName, imLabel)

    // 当前是否英文字模式（按子模式标签是否为纯 ASCII 字母判断）
    readonly property bool isAsciiMode: Data.isAsciiMode(imLabel)

    // 全量候选（展开列表用；addon 收到 expand 请求后写文件）
    property var allCandidates: []

    // ------------------------------------------------------------------

    function applyStatus(raw) {
        // 候选变了就顺手把全量拉一份：候选栏要按全量排列，
        // 排不下的进展开列表。放在这里而不是 card 的 onChanged ——
        // QML 里 property var 存数组时，内容变化不保证触发 onChanged
        // （实测 card 侧那个条件一次都没触发过）。
        // data.js 的 parseStatus 解析失败时返回上一次的副本，
        // 所以文件半写 / 还没生成的情况不会把候选闪空。
        const st = Data.parseStatus(raw, {
            items: candidates, preedit: preedit,
            visible: panelVisible, keyboard: imKeyboard, im: imName,
            imLabel: imLabel, imIcon: imIcon,
            hasPrev: hasPrev, hasNext: hasNext, hasMore: hasMore,
        })
        candidates = st.items
        preedit = st.preedit
        panelVisible = st.visible
        imKeyboard = st.keyboard
        imName = st.im
        imLabel = st.imLabel
        imIcon = st.imIcon
        hasPrev = st.hasPrev
        hasNext = st.hasNext
        hasMore = st.hasMore

        // 这里**不**拉全量：候选栏只监控前面十几个候选，全量是展开列表才需要的。
        // 全量要跨页遍历（rime 懒加载，取第 7 个得先生成下一页），
        // 一次几十毫秒，会卡住 fcitx5 的事件循环 —— 打字就变一格一格的。
        // 展开时由 card 的 onCandExpandedChanged 触发。
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
        } else if (line.startsWith("error:")) {
            lastError = line.substring(6)
            console.error("[inline-keyboard/fcitx] addon 报告: " + lastError)
        } else if (line.startsWith("allcand:")) {
            try {
                const arr = JSON.parse(line.substring(8))
                if (Array.isArray(arr))
                    allCandidates = arr
            } catch (e) {
                console.log("inline-keyboard/fcitx: 全量候选解析失败 " + e)
            }
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

    // 请求全量候选：addon 用 BulkCandidateList::candidateFromAll 一次取完。
    function requestAllCandidates() {
        expandProc.command = ["sh", "-c",
            "printf '1' > \"" + runtimeDir + "/inline-keyboard-expand\""]
        expandProc.running = true
    }

    // 选第 N 个候选：addon 读到后直接调 CandidateWord::select，
    // 不受输入法数字选词键限制，也能选到第 10 个以后。
    function selectCandidate(index) {
        if (index < 0)
            return
        selectProc.command = ["sh", "-c",
            "printf '" + index + "' > \"" + runtimeDir + "/inline-keyboard-select\""]
        selectProc.running = true
    }

    // ------------------------------------------------------------------

    Socket {
        id: socket
        path: bridge.socketPath
        // DataStream 不设 parser 就永远不会触发 read —— 连上了也收不到字节。
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => bridge.handleSocketData(data)
        }
    }

    // connected 是开关，初始 false 且不会自动连；断线（fcitx5 重启）也靠它重连。
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!socket.connected)
                socket.connected = true
        }
    }

    Process {
        id: expandProc
        command: ["sh", "-c", "true"]
    }

    Process {
        id: selectProc
        command: ["sh", "-c", "true"]
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

    // 全量候选也走推送：addon 收到 expand 请求后一次取完，直接推 allcand:{json}。
    // 不再轮询 inline-keyboard-allcand.json（文件只在 socket 没连上时由 probe.sh 用）。

    // 兼容旧调用名（daemon 的 requestAllCandidates 走这里）
    function requestAllCandidatesFromFile() {
        requestAllCandidates()
    }

}
