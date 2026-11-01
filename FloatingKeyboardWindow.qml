// 浮动模式的键盘窗口：可拖动、位置夹在屏幕内，尺寸用名义值（metrics.cardW / kbHeight）。
// 注意：不能用 card.width 夹边界 —— 卡片是 anchors.fill，会形成正反馈把窗口压窄。

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common

// 浮动键盘窗口：不贴边、可拖动。同样不抢键盘焦点。
PanelWindow {
    // 允许压到 DMS 条栏 / 状态栏上面：Overlay 层 + exclusionMode Ignore，posY 下界就是 0。
    // resize 拖动中卡片尺寸不变（宽高由 metrics 算，输入是 daemon 的 savedW/H，松手落盘后才更新），所以拖动中 mask 也不用重算。

    id: root

    property bool keyboardVisible: false
    property real kbWidth: 1050
    property real kbHeight: 444
    property bool showCandBar: root.fcitxCandidates.length > 0 || root.debugCandItems.length > 0
    property bool fnActive: false
    property bool escSwap: false
    property var modifierStates: ({
    })
    property string page: "page1"
    property string mode: "keys"
    property bool editing: false
    property bool avoidWindows: true
    property bool tooltips: true
    property bool voiceActive: false
    property bool voiceMinimal: false
    property bool voiceAvailable: false
    property real bgOpacity: 1
    property int repeatInterval: 60
    property real keyOpacity: 1
    property string specialKeyStyle: "full"
    property string winKeyStyle: "mod"
    property string winKeyCustomIcon: ""
    property real resizeW: 1050
    property real resizeH: 444
    property real baseKbWidth: 1050
    property real baseKbHeight: 444
    property bool dockFill: true
    property var actionList: []
    property var fcitxCandidates: []
    property bool fcitxImKeyboard: false
    property var debugCandItems: []
    property var allCandidates: []
    property int candRevision: 0
    property bool fcitxHasMore: false
    property string fcitxImIcon: ""
    property string fcitxImLabel: ""
    property bool fcitxPreeditEmbedded: false
    property string fcitxPreedit: ""
    property bool fcitxVisible: false
    property string slotActionId: "float"
    property var quickBarActions: []
    property var imList: []
    property var imRows: []
    // 窗口左上角位置（拖动把手时更新）
    property var controller: null
    property real posX: 100
    property real posY: 100
    // 拖动开始时的位置（translation 是累计位移，必须基于起点算，不能拿当前值累加）
    property real dragStartX: 0
    property real dragStartY: 0
    // 首次显示时才定位，之后保持拖动后的位置
    property bool posInitialized: false
    readonly property real preeditReserve: Math.round(metrics.candH * 0.95)
    // 卡片位置在这里统一算，mask 和卡片本体共用。
    // mask 声明在 card 之前，直接读 card.x/card.y 会拿到 undefined（输入区变 0、点不动）
    readonly property real cardX: Math.round(Math.max(0, root.posX))
    readonly property real cardY: Math.round(Math.max(0, root.posY))
    readonly property real preeditTop: Math.max(0, cardY - root.preeditReserve)
    property var cardRef: null

    signal voiceMicRequested()
    signal opacityAdjusted(real bg, real key)
    signal resizeCommitRequested()
    signal resizeCloseRequested()
    signal resizeCancelRequested()
    signal resizeResetRequested()
    signal resizeFillToggleRequested()
    signal modeChangeRequested(string mode)
    signal allCandidatesRequested()
    signal quickBarChanged(var list)
    signal quickAction(string action)
    signal voiceMinimalRequested()
    signal discardVoiceRequested()
    signal imSwitchRequested()
    signal imCycleRequested()
    signal selectCandidateRequested(int index)
    signal imSelected(string name, var ascii)
    signal orderChanged(var orderedActions)
    signal slotChanged(string actionId)
    signal keyboardClosed()
    signal keyPressed(var keyData)
    signal modifierPressed(var keyData)
    signal modifierReleased(var keyData)
    signal textCommitRequested(string text)

    function show() {
        keyboardVisible = true;
        if (!posInitialized) {
            // 上次拖到的位置；没记录过就用默认（居中、距底 120）
            const sx = root.controller ? root.controller.floatPosX : -1;
            const sy = root.controller ? root.controller.floatPosY : -1;
            if (sx >= 0 && sy >= 0) {
                // 记下的位置可能来自别的分辨率，先夹回屏幕内再摆
                posX = Math.max(0, Math.min(metrics.screenW - metrics.cardW, sx));
                posY = Math.max(0, Math.min(metrics.screenH - root.kbHeight, sy));
            } else {
                posX = Math.max(0, (metrics.screenW - metrics.cardW) / 2);
                posY = Math.max(0, metrics.screenH - root.kbHeight - Theme.spacingXL * 5);
            }
            posInitialized = true;
        }
    }

    function hide() {
        if (!keyboardVisible)
            return ;

        keyboardVisible = false;
        keyboardClosed();
    }

    // 首次定位是 show() 摆出来的，不是用户拖的，别写盘
    onPosXChanged: if (posInitialized) posSaveTimer.restart()
    onPosYChanged: if (posInitialized) posSaveTimer.restart()
    visible: keyboardVisible && !root.voiceMinimal
    color: "transparent"
    implicitWidth: metrics.screenW
    implicitHeight: metrics.screenH
    WlrLayershell.namespace: "dms:plugins:inlineKeyboard:floating"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // 关键：不参与独占区计算，否则会一直被 DMS 条栏的 exclusive zone 推开，永远压不到条栏上面，而且条栏换到底部时同样会被推
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    Component.onCompleted: cardRef = card

    // 拖动中每帧都在改位置，停手再写盘
    Timer {
        id: posSaveTimer

        interval: 400
        onTriggered: {
            if (root.controller)
                root.controller.saveFloatPosition(root.posX, root.posY);

        }
    }

    KeyboardMetrics {
        id: metrics

        kbWidth: root.kbWidth
        kbHeight: root.kbHeight
        showCandBar: root.showCandBar
        screenW: root.screen ? root.screen.width : 1280
        screenH: root.screen ? root.screen.height : 800
    }

    // 窗口**必须铺满整屏**。浮在屏幕上的键盘不能用一个「和键盘一样大」的窗口：调整尺寸时窗口尺寸跟着变，margins 重算，键盘位置就会漂；
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    KeyboardCard {
        id: card

        onOpacityAdjusted: (bg, key) => {
            return root.opacityAdjusted(bg, key);
        }
        // 窗口是全屏的，卡片绝对定位。宽高不在这里设 ——
        // 卡片自己绑了 resizeW/H，拖动时才会实时跟着变
        x: root.cardX
        y: root.cardY
        unit: metrics.unit
        keyH: metrics.keyH
        gap: metrics.gap
        pad: metrics.pad
        candH: metrics.candH
        designScale: metrics.uiScale
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
        tooltips: root.tooltips
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
        onResizeOriginShift: (dx, dy) => {
            const maxX = Math.max(0, metrics.screenW - metrics.cardW);
            const maxY = Math.max(0, metrics.screenH - Math.round(card.height));
            root.posX = Math.max(0, Math.min(maxX, root.posX + dx));
            root.posY = Math.max(0, Math.min(maxY, root.posY + dy));
        }
        onResizeCloseRequested: root.resizeCloseRequested()
        onResizeCancelRequested: root.resizeCancelRequested()
        onResizeResetRequested: root.resizeResetRequested()
        onResizeFillToggleRequested: root.resizeFillToggleRequested()
        onVoiceMinimalRequested: root.voiceMinimalRequested()
        onDiscardVoiceRequested: root.discardVoiceRequested()
        onVoiceMicRequested: root.voiceMicRequested()
        onModeChangeRequested: (mode) => {
            return root.modeChangeRequested(mode);
        }
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
        imRows: root.imRows
        onQuickBarChanged: (list) => {
            return root.quickBarChanged(list);
        }
        onEditingChanged: root.editing = editing
        onQuickAction: (action) => {
            return root.quickAction(action);
        }
        onImSwitchRequested: root.imSwitchRequested()
        onImCycleRequested: root.imCycleRequested()
        onSelectCandidateRequested: (index) => {
            return root.selectCandidateRequested(index);
        }
        onImSelected: (name, ascii) => {
            return root.imSelected(name, ascii);
        }
        onOrderChanged: (list) => {
            return root.orderChanged(list);
        }
        onSlotChanged: (id) => {
            return root.slotChanged(id);
        }
        onKeyPressed: (keyData) => {
            return root.keyPressed(keyData);
        }
        onModifierPressed: (keyData) => {
            return root.modifierPressed(keyData);
        }
        onModifierReleased: (keyData) => {
            return root.modifierReleased(keyData);
        }
        onTextCommitRequested: (text) => {
            return root.textCommitRequested(text);
        }
        onAllCandidatesRequested: root.allCandidatesRequested()
        // 松手时的落点判断在 onDragMoved 里按「起点 + 累计位移」算，起点在 onDragStarted 记一次
        onDragStarted: {
            root.dragStartX = root.posX;
            root.dragStartY = root.posY;
        }
        onDragMoved: (dx, dy) => {
            // 必须用"名义尺寸"（metrics.cardW / kbHeight）夹紧：用 card.width 会踩到"窗口被压窄 → 允许位移更大 → 更溢出"的正反馈
            const maxX = Math.max(0, metrics.screenW - metrics.cardW);
            const maxY = Math.max(0, metrics.screenH - root.kbHeight);
            root.posX = Math.max(0, Math.min(maxX, root.dragStartX + dx));
            root.posY = Math.max(0, Math.min(maxY, root.dragStartY + dy));
        }
    }

    // 输入区 = 卡片 + 卡片上方那条预编辑标签，其余整屏穿透。
    // 窗口铺满整屏，这里漏设或算 0 的话，要么全屏点不动、要么挡住桌面。
    mask: Region {
        x: cardX
        y: preeditTop
        // 读卡片自己的宽高：metrics 算出来的值取整后才是真实边界
        width: root.visible ? Math.round(card.width) : 0
        height: root.visible ? Math.round(cardY + card.height - preeditTop) : 0
    }

}
