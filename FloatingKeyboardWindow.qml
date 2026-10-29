// 浮动模式的键盘窗口：可拖动、位置夹在屏幕内，尺寸用名义值（metrics.cardW / kbHeight）。
// 注意：不能用 card.width 夹边界 —— 卡片是 anchors.fill，会形成正反馈把窗口压窄。
// 几何推导集中在 KeyboardMetrics（与停靠窗口共用）。

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// 浮动键盘窗口：不贴边、可拖动。同样不抢键盘焦点。
PanelWindow {
    id: root

    property bool keyboardVisible: false
    property real kbWidth: 1050
    property real kbHeight: 444
    property real gap: 6
    property real candH: 44
    // 有候选才占位显示候选栏（数据来自 fcitx5 addon）
    // 判据对齐 fcitx5 自身行为：这个输入法子项会不会弹候选窗。
    //   · rime 中文（万）：会 → 有候选时显示
    //   · rime abc：英文直接上屏，fcitx5 不弹候选窗 → 不显示
    //   · keyboard-us：纯键盘布局 → 不显示
    // 高度由 topArea 固定预留（candH），所以显隐不会让键盘跳动。
    property bool showCandBar:
        root.fcitxCandidates.length > 0 || root.debugCandItems.length > 0

    property bool fnActive: false
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定），由 daemon 整体替换
    property var modifierStates: ({})
    property string page: "page1"
    property string mode: "keys"
    property bool editing: false
    property bool avoidWindows: true
    // 语音输入是否在录音（决定顶部是否切到语音行）
    property bool voiceActive: false
    // 语音模式：只留顶部语音行
    property bool voiceMinimal: false
    signal voiceMicRequested()
    // vinput 是否可用（可选扩展，没装就禁用语音动作）
    property bool voiceAvailable: false
    property real bgOpacity: 1.0
    property int repeatInterval: 60
    property real keyOpacity: 1.0
    // 特殊键形态设置（见 layouts/special-keys.js）
    property string specialKeyStyle: "full"
    property string winKeyStyle: "mod"
    property string winKeyCustomIcon: ""
    // 调整大小：预览尺寸 / 名义尺寸 / 屏幕尺寸
    property real resizeW: 1050
    property real resizeH: 444
    property real baseKbWidth: 1050
    property real baseKbHeight: 444
    signal resizeCommitRequested()
    signal resizeCloseRequested()
    signal resizeCancelRequested()
    signal resizeResetRequested()
    signal resizeFillToggleRequested()
    signal modeChangeRequested(string mode)
    // 停靠时是否横向铺满屏幕
    property bool dockFill: true
    property var actionList: []
    // fcitx5 候选（由 daemon 从 inline-keyboard-status.json 读入）
    property var fcitxCandidates: []
    // 当前输入法是否纯键盘布局（无候选能力）
    property bool fcitxImKeyboard: false
    // 调试候选（daemon 的 debugCand 注入），非空时优先显示
    property var debugCandItems: []
    // 全量候选（daemon 从 FcitxBridge 转发）
    property var allCandidates: []
    property int candRevision: 0
    signal allCandidatesRequested()
    property bool fcitxHasMore: false
    property string fcitxImIcon: ""
    property string fcitxImLabel: ""
    property bool fcitxPreeditEmbedded: false
    property string fcitxPreedit: ""
    property bool fcitxVisible: false
    property string slotActionId: "float"
    property var quickBarActions: []
    signal quickBarChanged(var list)
    signal quickAction(string action)
    signal voiceMinimalRequested()
    property var imList: []
    signal imSwitchRequested()
    signal imListRequested()
    signal imCycleRequested()
    signal selectCandidateRequested(int index)
    signal imSelected(string name)
    signal orderChanged(var orderedActions)
    signal slotChanged(string actionId)
    signal keyboardClosed
    signal keyPressed(var keyData)
    signal modifierPressed(var keyData)
    signal modifierReleased(var keyData)
    // 表情 / 符号页点上屏（转给 daemon）
    signal textCommitRequested(string text)

    // 窗口左上角位置（拖动把手时更新）
    property real posX: 100
    property real posY: 100
    // 拖动开始时的位置（translation 是累计位移，必须基于起点算，不能拿当前值累加）
    property real dragStartX: 0
    property real dragStartY: 0
    // 首次显示时才定位，之后保持拖动后的位置
    property bool posInitialized: false

    KeyboardMetrics {
        id: metrics
        kbWidth: root.kbWidth
        kbHeight: root.kbHeight
        gap: root.gap
        candH: root.candH
        showCandBar: root.showCandBar
        screenW: root.screen ? root.screen.width : 1280
        screenH: root.screen ? root.screen.height : 800
    }

    // 允许压到 DMS 条栏 / 状态栏上面：Overlay 层 + exclusionMode Ignore，
    // 所以 posY 下界就是 0（原来夹在条栏高度下面，永远盖不住）

    function show() {
        keyboardVisible = true
        if (!posInitialized) {
            posX = Math.max(0, (metrics.screenW - metrics.cardW) / 2)
            posY = Math.max(0, metrics.screenH - root.kbHeight - 120)
            posInitialized = true
        }
    }

    function hide() {
        if (!keyboardVisible)
            return
        keyboardVisible = false
        keyboardClosed()
    }

    visible: keyboardVisible && !root.voiceMinimal
    color: "transparent"

    // 窗口**必须铺满整屏**。浮在屏幕上的键盘不能用一个「和键盘一样大」的窗口：
    // 调整尺寸时窗口尺寸跟着变，margins 重算，键盘位置就会漂；
    // 而且窗口边缘之外的点按和拖拽全落在窗口外，表现很怪。
    // 触控范围交给下面的 mask 精确限定在卡片上。
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    implicitWidth: metrics.screenW
    implicitHeight: metrics.screenH
    readonly property real preeditReserve: Math.round(root.candH * 0.95)
    // 卡片位置在这里统一算，mask 和卡片本体共用。
    // mask 声明在 card 之前，直接读 card.x/card.y 会拿到 undefined（输入区变 0、点不动）
    readonly property real cardX: Math.round(Math.max(0, root.posX))
    readonly property real cardY: Math.round(Math.max(0, root.posY))
    readonly property real preeditTop: Math.max(0, cardY - root.preeditReserve)


    WlrLayershell.namespace: "dms:plugins:inlineKeyboard:floating"
    // Overlay：要盖住 DMS 的 Top 层面板（launcher / 设置页）才能在里面打字。
    // 实测 niri 对 Overlay 层的 exclusiveZone 一样计入（1030 → 586，正好 444），
    // 「避让不够」是窗口自身最小高度的限制，与层无关
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // 关键：不参与独占区计算，否则会一直被 DMS 条栏的 exclusive zone 推开，
    // 永远压不到条栏上面，而且条栏换到底部时同样会被推
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    // 输入区 = 卡片 + 卡片上方那条预编辑标签，其余整屏穿透。
    // 窗口铺满整屏，这里漏设或算 0 的话，要么全屏点不动、要么挡住桌面。
    mask: Region {
        x: cardX
        y: preeditTop
        // 读卡片自己的宽高：metric 算出来的值取整后才是真实边界
        //（踩过的坑是 mask 里读 card.y —— 那要求构造期就有值，结果输入区变 0、点不动）
        width: root.visible ? Math.round(card.width) : 0
        height: root.visible ? Math.round(cardY + card.height - preeditTop) : 0
        // 注意：resize 拖动中卡片尺寸并不会变（卡片宽高由 metrics 算，而 metrics
        // 的输入是 daemon 的 savedW/H，松手落盘后才更新），所以拖动中 mask 也不变，
        // 指针移出输入区靠隐式 grab 维持；松手后这里自然重算。
    }

    // 供外部（daemon 的调试 IPC）访问卡片状态
    // 用 onCompleted 赋值而不是 `property var cardRef: card`：
    // 引用 id 的前向绑定在构造期可能拿到 undefined，且之后不会重算（docked 那边就踩到了）
    property var cardRef: null
    Component.onCompleted: cardRef = card

    KeyboardCard {
        id: card

        // 窗口是全屏的，卡片绝对定位。宽高不在这里设 ——
        // 卡片自己绑了 resizeW/H，拖动时才会实时跟着变
        x: root.cardX
        y: root.cardY

        unit: metrics.unit
        keyH: metrics.keyH
        gap: root.gap
        pad: metrics.pad
        candH: root.candH
        showCandBar: root.showCandBar
        debugCandItems: root.debugCandItems
        allCandidates: root.allCandidates
        candRevision: root.candRevision
        handleH: metrics.handleH
        quickH: metrics.quickH
        showHandle: true
        dragEnabled: true
        repeatInterval: root.repeatInterval
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
        specialKeyStyle: root.specialKeyStyle
        winKeyStyle: root.winKeyStyle
        winKeyCustomIcon: root.winKeyCustomIcon
        resizeW: root.resizeW
        resizeH: root.resizeH
        baseKbWidth: root.baseKbWidth
        baseKbHeight: root.baseKbHeight
        screenW: root.screen ? root.screen.width : 1920
        screenH: root.screen ? root.screen.height : 1080
        onResizeCommitRequested: root.resizeCommitRequested()
        // 落盘后尺寸变了，位置补一下：拖左边/上边时对侧要钉住不动。
        // 补偿完再统一夹回屏幕：新尺寸可能把卡片顶出右/下沿，而别处没有
        // 位置 clamp 把它拉回来（拖动改位置那条路径只在自己那条链里夹）。
        onResizeOriginShift: (dx, dy) => {
            const maxX = Math.max(0, metrics.screenW - metrics.cardW)
            const maxY = Math.max(0, metrics.screenH - Math.round(card.height))
            root.posX = Math.max(0, Math.min(maxX, root.posX + dx))
            root.posY = Math.max(0, Math.min(maxY, root.posY + dy))
        }
        onResizeCloseRequested: root.resizeCloseRequested()
        onResizeCancelRequested: root.resizeCancelRequested()
        onResizeResetRequested: root.resizeResetRequested()
        onResizeFillToggleRequested: root.resizeFillToggleRequested()
        onVoiceMinimalRequested: root.voiceMinimalRequested()
        onVoiceMicRequested: root.voiceMicRequested()
        onModeChangeRequested: mode => root.modeChangeRequested(mode)
        dockFill: root.dockFill
        actionList: root.actionList
        fcitxCandidates: root.fcitxCandidates
        fcitxImKeyboard: root.fcitxImKeyboard
        fcitxHasMore: root.fcitxHasMore
        fcitxImIcon: root.fcitxImIcon
        fcitxImLabel: root.fcitxImLabel
        fcitxPreeditEmbedded: root.fcitxPreeditEmbedded
        fcitxPreedit: root.fcitxPreedit
        fcitxVisible: root.fcitxVisible
        slotActionId: root.slotActionId
        quickBarActions: root.quickBarActions
        isFloating: true
        imList: root.imList

        onQuickBarChanged: list => root.quickBarChanged(list)
        onEditingChanged: root.editing = editing
        onQuickAction: action => root.quickAction(action)
        onImSwitchRequested: root.imSwitchRequested()
        onImListRequested: root.imListRequested()
        onImCycleRequested: root.imCycleRequested()
        onSelectCandidateRequested: index => root.selectCandidateRequested(index)
        onImSelected: name => root.imSelected(name)
        onOrderChanged: list => root.orderChanged(list)
        onSlotChanged: id => root.slotChanged(id)
        onKeyPressed: keyData => root.keyPressed(keyData)
        onModifierPressed: keyData => root.modifierPressed(keyData)
        onModifierReleased: keyData => root.modifierReleased(keyData)
        onTextCommitRequested: text => root.textCommitRequested(text)
        onAllCandidatesRequested: root.allCandidatesRequested()

        // 松手时的落点判断在 onDragMoved 里按「起点 + 累计位移」算，
        // 起点在 onDragStarted 记一次
        onDragStarted: {
            root.dragStartX = root.posX
            root.dragStartY = root.posY
        }
        onDragMoved: (dx, dy) => {
            // 必须用"名义尺寸"（metrics.cardW / kbHeight）夹紧：
            // 用 card.width 会踩到"窗口被压窄 → 允许位移更大 → 更溢出"的正反馈
            const maxX = Math.max(0, metrics.screenW - metrics.cardW)
            const maxY = Math.max(0, metrics.screenH - root.kbHeight)
            root.posX = Math.max(0, Math.min(maxX, root.dragStartX + dx))
            root.posY = Math.max(0, Math.min(maxY, root.dragStartY + dy))
        }
    }
}
