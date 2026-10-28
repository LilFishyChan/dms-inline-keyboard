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
    property bool showCandBar: root.fcitxCandidates.length > 0
        && !root.fcitxImKeyboard

    property bool fnActive: false
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定），由 daemon 整体替换
    property var modifierStates: ({})
    property string page: "page1"
    property string mode: "keys"
    property bool editing: false
    property bool avoidWindows: true
    property real bgOpacity: 1.0
    property real keyOpacity: 1.0
    property var actionList: []
    // fcitx5 候选（由 daemon 从 inline-keyboard-status.json 读入）
    property var fcitxCandidates: []
    // 当前输入法是否纯键盘布局（无候选能力）
    property bool fcitxImKeyboard: false
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

    visible: keyboardVisible
    color: "transparent"

    // 从底部锚定：顶部锚定的 margin 是相对"可用区域"（DMS 条栏的独占区）算的，
    // 那样 posY 永远到不了 0，键盘也就压不住条栏
    anchors {
        bottom: true
        left: true
    }
    margins {
        bottom: Math.round(metrics.screenH - root.posY - root.kbHeight)
        left: Math.round(root.posX)
    }

    implicitWidth: metrics.cardW
    // 候选出现且有拼音原文时，顶部要额外留出一块给浮动的原文标签。
    // card 是底部对齐的，所以多出来的高度只影响窗口（键盘整体位置不变），
    // 标签不会被窗口裁掉。
    // 预编辑标签浮在卡片上方，所以窗口要预留它的高度。
    // 关键：**恒定预留**。原来按「当前有没有 preedit」动态加减 42px，
    // 打字时整个键盘（连 exclusiveZone）会忽高忽低，下面的窗口跟着抖。
    readonly property real preeditReserve: Math.round(root.candH * 0.95)
    implicitHeight: root.kbHeight + preeditReserve

    WlrLayershell.namespace: "dms:plugins:inlineKeyboard:floating"
    // Overlay：要盖住 DMS 的 Top 层面板（launcher / 设置页）才能在里面打字。
    // 实测 niri 对 Overlay 层的 exclusiveZone 一样计入（1030 → 586，正好 444），
    // 「避让不够」是窗口自身最小高度的限制，与层无关
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // 关键：不参与独占区计算，否则会一直被 DMS 条栏的 exclusive zone 推开，
    // 永远压不到条栏上面，而且条栏换到底部时同样会被推
    WlrLayershell.exclusionMode: WlrLayershell.Ignore

    // 不要用 Region { item: card }：card 之外的部分会被裁掉，
    // 而 preedit 标签正是浮在 card 上方那 42px 里。
    mask: Region {
        item: maskArea
    }

    Item {
        id: maskArea
        anchors.fill: parent
    }

    // 供外部（daemon 的调试 IPC）访问卡片状态
    // 用 onCompleted 赋值而不是 `property var cardRef: card`：
    // 引用 id 的前向绑定在构造期可能拿到 undefined，且之后不会重算（docked 那边就踩到了）
    property var cardRef: null
    signal allCandidatesRequested()
    property var allCandidates: []
    Component.onCompleted: cardRef = card

    onAllCandidatesRequested: root.allCandidatesRequested()

    KeyboardCard {
        id: card

        anchors.fill: parent

        unit: metrics.unit
        keyH: metrics.keyH
        gap: root.gap
        pad: metrics.pad
        candH: root.candH
        showCandBar: root.showCandBar
        handleH: metrics.handleH
        quickH: metrics.quickH
        showHandle: true
        dragEnabled: true
        fnActive: root.fnActive
        escSwap: root.escSwap
        modifierStates: root.modifierStates
        page: root.page
        mode: root.mode
        editing: root.editing
        avoidWindows: root.avoidWindows
        bgOpacity: root.bgOpacity
        keyOpacity: root.keyOpacity
        actionList: root.actionList
        fcitxCandidates: root.fcitxCandidates
        allCandidates: root.allCandidates
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
