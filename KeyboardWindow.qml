// 停靠模式的键盘窗口：layer-shell 贴在屏幕底部，宽度铺满。
// implicitWidth/Height 必须用名义值（metrics.cardW / kbHeight）：绑 card.width

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
    // 语音输入是否在录音（决定顶部是否切到语音行）
    property bool voiceActive: false
    // 语音模式：只留顶部语音行
    property bool voiceMinimal: false
    signal voiceMicRequested()
    signal opacityAdjusted(real bg, real key)
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
    // 用户设置的键盘名义宽高（逻辑像素），按键尺寸由它们推导
    property real kbWidth: 1050
    property real kbHeight: 444
    property real gap: 6
    property real candH: 44
    // 有候选才占位显示候选栏（数据来自 fcitx5 addon）
    // 判据对齐 fcitx5 自身行为：这个输入法子项会不会弹候选窗。
    property bool showCandBar:
        root.fcitxCandidates.length > 0 || root.debugCandItems.length > 0

    // 由 daemon 托管的键盘状态
    property bool fnActive: false
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定），由 daemon 整体替换
    property var modifierStates: ({})
    property string page: "page1"
    property string mode: "keys"
    property bool editing: false
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

    KeyboardMetrics {
        id: metrics
        kbWidth: root.kbWidth
        kbHeight: root.kbHeight
        gap: root.gap
        candH: root.candH
        showCandBar: root.showCandBar
        screenW: root.screen ? root.screen.width : 1280
        screenH: root.screen ? root.screen.height : 800
        // 停靠模式贴屏幕两侧；关掉「铺满」时回到名义宽度并居中
        fillWidth: root.dockFill
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

    visible: keyboardVisible && !root.voiceMinimal

    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }

    // 避让：reserve 面板实际高度（cardHeight，已扣掉上下留白与把手前的间隙）。
    // 用 saveH 的原始 kbHeight 会多留 pad+gap，下面的窗口被无谓地推远一截。
    exclusiveZone: (keyboardVisible && avoidWindows) ? Math.ceil(metrics.cardHeight) : 0

// 只包住键盘本体：铺满整屏会让 exclusiveZone 失效（避让和全屏不可兼得）
    implicitWidth: metrics.screenW
    // 候选出现且有拼音原文时，顶部要额外留出一块给浮动的原文标签。
    // card 是底部对齐的，所以多出来的高度只影响窗口（键盘整体位置不变），
    readonly property real preeditReserve: Math.round(root.candH * 0.95)
    implicitHeight: metrics.cardHeight + preeditReserve

    WlrLayershell.namespace: "dms:plugins:inlineKeyboard"
    // Overlay：要盖住 DMS 的 Top 层面板（launcher / 设置页）才能在里面打字。
    // 实测 niri 对 Overlay 层的 exclusiveZone 一样计入（1030 → 586，正好 444），
    WlrLayershell.layer: WlrLayer.Overlay
    // 键盘自己不发按键（由 ydotool 注入），绝不能抢焦点
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // 输入区域：只盖住卡片本体 + 它上方的预编辑标签，其余部分穿透。
    // 窗口本身铺满屏幕宽（left/right 锚定），如果 mask 也跟着铺满，
    mask: Region {
        x: Math.round(card.x)
        y: Math.max(0, Math.round(card.y - root.preeditReserve))
        // 窗口隐藏时必须把输入区域也收成 0：visible=false 只是不绘制，
        // layer surface 的 mask 还留在屏幕上继续吃点击
        width: root.visible ? Math.round(card.width) : 0
        height: root.visible ? Math.max(0, Math.round(root.height - Math.max(0,
                Math.round(card.y - root.preeditReserve)))) : 0
    }

    // 供外部（daemon 的调试 IPC）访问卡片状态
    // 用 onCompleted 赋值而不是 `property var cardRef: card`：
    property var cardRef: null
    Component.onCompleted: cardRef = card

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
        debugCandItems: root.debugCandItems
        allCandidates: root.allCandidates
        candRevision: root.candRevision
        handleH: metrics.handleH
        quickH: metrics.quickH
        showHandle: true
        dragEnabled: false
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
        onResizeCloseRequested: root.resizeCloseRequested()
        onResizeCancelRequested: root.resizeCancelRequested()
        onResizeResetRequested: root.resizeResetRequested()
        onResizeFillToggleRequested: root.resizeFillToggleRequested()
        onVoiceMinimalRequested: root.voiceMinimalRequested()
        onVoiceMicRequested: root.voiceMicRequested()
        onModeChangeRequested: mode => root.modeChangeRequested(mode)
        onOpacityAdjusted: (bg, key) => root.opacityAdjusted(bg, key)
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
        isFloating: false
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
    }
}
