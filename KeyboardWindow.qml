// 停靠模式的键盘窗口：layer-shell 贴在屏幕底部，宽度铺满。
// 几何推导集中在 KeyboardMetrics（与浮动窗口共用），本文件只负责锚定与避让。
// implicitWidth/Height 必须用名义值（metrics.cardW / kbHeight）：绑 card.width
// 会形成「窗口 ← 卡片 ← 窗口」的循环，浮动窗口一拖就自我收缩。

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

// 贴底键盘窗口。layer-shell overlay、不抢键盘焦点（注入的按键落到应用上）。
PanelWindow {
    id: root

    property bool keyboardVisible: false
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
    // 用户设置的键盘名义宽高（逻辑像素），按键尺寸由它们推导
    property real kbWidth: 1050
    property real kbHeight: 444
    property real gap: 6
    property real candH: 44
    // 有候选才占位显示候选栏（数据来自 fcitx5 addon）
    property bool showCandBar: root.fcitxCandidates.length > 0
        && !root.fcitxImKeyboard

    // 由 daemon 托管的键盘状态
    property bool fnActive: false
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定），由 daemon 整体替换
    property var modifierStates: ({})
    property string page: "page1"
    property string mode: "keys"
    property bool editing: false
    signal quickAction(string action)
    property string imName: ""
    property var imList: []
    property string imIconFile: ""
    property int imIconVersion: 0
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

    function show() {
        keyboardVisible = true
    }

    function hide() {
        if (!keyboardVisible)
            return
        keyboardVisible = false
        keyboardClosed()
    }

    visible: keyboardVisible
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    // 避让：reserve 键盘实际高度（窗口自身高度，已含上下留白与快捷栏），关闭时归零
    // 避让高度只算键盘本体（kbHeight），不含预编辑预留区。
    // 那块是浮在卡片上方的标签，压在应用内容上没关系；
    // 算进 exclusiveZone 会把下面的窗口无谓地往上推 42px。
    exclusiveZone: (keyboardVisible && avoidWindows) ? Math.ceil(root.kbHeight) : 0

    implicitWidth: metrics.cardW
    // 候选出现且有拼音原文时，顶部要额外留出一块给浮动的原文标签。
    // card 是底部对齐的，所以多出来的高度只影响窗口（键盘整体位置不变），
    // 标签不会被窗口裁掉。
    // 预编辑标签浮在卡片上方，所以窗口要预留它的高度。
    // 关键：**恒定预留**。原来按「当前有没有 preedit」动态加减 42px，
    // 打字时整个键盘（连 exclusiveZone）会忽高忽低，下面的窗口跟着抖。
    readonly property real preeditReserve: Math.round(root.candH * 0.95)
    implicitHeight: root.kbHeight + preeditReserve

    WlrLayershell.namespace: "dms:plugins:inlineKeyboard"
    // Overlay：要盖住 DMS 的 Top 层面板（launcher / 设置页）才能在里面打字。
    // 实测 niri 对 Overlay 层的 exclusiveZone 一样计入（1030 → 586，正好 444），
    // 「避让不够」是窗口自身最小高度的限制，与层无关
    WlrLayershell.layer: WlrLayer.Overlay
    // 键盘自己不发按键（由 ydotool 注入），绝不能抢焦点
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

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

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        unit: metrics.unit
        keyH: metrics.keyH
        gap: root.gap
        pad: metrics.pad
        candH: root.candH
        showCandBar: root.showCandBar
        handleH: metrics.handleH
        quickH: metrics.quickH
        showHandle: true
        dragEnabled: false
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
        isFloating: false
        imName: root.imName
        imList: root.imList
        imIconFile: root.imIconFile
        imIconVersion: root.imIconVersion

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
    }
}
