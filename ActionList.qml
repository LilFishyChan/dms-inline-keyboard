// Inline Keyboard 的功能动作列表：4 行滚动网格 + 底部编辑按钮；
// 编辑态下可拖动排序、拖到顶部快捷栏/右上角槽。
import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets
import "Motion.js" as Motion
import "actions.js" as Actions

Item {
    id: functionsArea

    // KeyboardCard 根：状态、函数、信号都从这里取
    property var controller: null

    // 把滚动视图交给 controller——落点计算需要它的坐标系
    Component.onCompleted: {
        if (controller)
            controller.actionListRef = fnScroll
    }
    Component.onDestruction: {
        if (controller && controller.actionListRef === fnScroll)
            controller.actionListRef = null
    }

    // 上面 4 行是滚动视图，底部留一行放「编辑」笔按钮
    anchors.fill: parent
    visible: controller.mode === "functions"

    // 拖动时的自动滚动速度（px/帧，正数向下）。由拖动事件按「离边缘多近」算出，
    // 做成常驻 Timer 而不是在手势回调里一次性挪 —— 手指停在边缘不动时也要继续滚。
    property real autoScrollSpeed: 0
    readonly property int autoScrollMaxSpeed: 18

    Timer {
        id: autoScrollTimer
        interval: 16
        repeat: true
        running: functionsArea.autoScrollSpeed !== 0 && controller.dragActive
        onTriggered: {
            const maxY = Math.max(0, fnScroll.contentHeight - fnScroll.height)
            const next = Math.max(0, Math.min(maxY, fnScroll.contentY + functionsArea.autoScrollSpeed))
            if (next === fnScroll.contentY) {
                functionsArea.autoScrollSpeed = 0
                return
            }
            fnScroll.contentY = next
            // 内容动了，落点要跟着重算（否则幽灵块停在旧位置）
            controller.updateTargetFromGhost()
            controller.updateDropTargets()
        }
    }

    readonly property real rowH: controller.keyH
    // 4 行滚动 + 1 行编辑按钮 = 键区那 5 行，所以功能页与键盘页高度一致
    readonly property int visibleRows: 4
    readonly property real scrollH: rowH * visibleRows + controller.gap * (visibleRows - 1)
    // 列数的唯一来源在卡片（落点计算 dropIndexAt 也用同一个值），这里不再硬编码 4
    readonly property int columns: controller.actionListColumns
    readonly property real cellW: (fnScroll.width - (columns - 1) * controller.gap) / columns

    // 拖到了「无效位置」：既不在列表里，也不在快捷栏 / 右上角槽上。
    // 否则整列前移，看着像要把这一项删掉。
    readonly property bool dropNoop: controller !== null && controller.dragActive
        && controller.dragIndex >= 0
        && controller.dragTarget < 0
        && !controller.dragOverBar && !controller.dragOverSlot

    // 幽灵块该画在第几格 —— 松手后这一项实际会落到的格子（见 listGhostIndex）。
    // 无效落点（拖到键盘外）时松手不调整顺序，幽灵回它自己那一格。
    readonly property int slotInsertIndex: (controller && controller.dragOverSlot
                                            && controller.dragIndex >= 0
                                            && controller.rightSlot)
        ? controller.dragIndex : -1

    readonly property int ghostPlaceIndex: {
        if (!controller || !controller.ghostAction)
            return -1
        return Actions.listGhostIndex({
            dragIndex: controller.dragIndex,
            dragTarget: controller.dragTarget,
            count: (controller.availableActions || []).length,
            dropNoop: functionsArea.dropNoop,
            insertAt: functionsArea.slotInsertIndex
        })
    }

    // 编辑态顶部空出的一行：拖动提示
    Item {
        id: editHint
        opacity: controller.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: controller.keyH

        Text {
            anchors.centerIn: parent
            text: controller.tr("Hold and drag to customise")
            color: Theme.withAlpha(controller.fg, 0.6)
            font.pixelSize: Math.max(11, Math.round(controller.keyH * 0.26))
        }
    }

    // 编辑态底色：surfaceContainerLow，衬出可拖动的区域
    Rectangle {
        // 跟随背景透明度
        opacity: (controller.editing ? 1 : 0) * (controller ? controller.bgOpacity : 1)
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
        }
        anchors.left: fnScroll.left
        anchors.right: fnScroll.right
        y: fnScroll.y
        height: fnScroll.height
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerLow
    }

    DFlickable {
        id: fnScroll
        // 左右各让出半个按键：列表宽度 = 键盘内容宽 - 1 个单位
        anchors.left: parent.left
        anchors.leftMargin: controller.unit / 2
        anchors.right: parent.right
        anchors.rightMargin: controller.unit / 2
        // 编辑态整体下移一行（带过渡）。这里只能用 y，不能同时设 anchors.top
        y: controller.editing ? controller.keyH : 0
        Behavior on y {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.panel; easing.type: Easing.OutCubic }
        }
        height: functionsArea.scrollH
        clip: true
        // 按住 100ms 才把 press 送给格子（DragInitiator）：延时内就开始滑的话
        // press 不送达，滚动照常。编辑态要同时能滚和能拖，靠这一条分工。
        pressDelay: 100
        contentHeight: fnGrid.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Item {
            id: fnGrid
            width: fnScroll.width
            readonly property int count: (controller.availableActions || []).length
            // 幽灵落在 count 格（只可能发生在「从快捷栏拖进来」），而 count 又正好
            // 是列数的整数倍时，那一格在下一行 —— 得把网格临时撑高一行才看得见。
            readonly property bool extraRow: controller.ghostAction !== null
                && count > 0 && functionsArea.ghostPlaceIndex >= count
                && count % Math.max(1, functionsArea.columns) === 0
            height: (Math.max(1, Math.ceil(count / functionsArea.columns)) + (extraRow ? 1 : 0))
                    * (controller.keyH + controller.gap) - controller.gap

            // 目标位置：松开后动作会落到这里（幽灵块样式，和固定栏一致）
            GhostBlock {
                id: dropShadow
                // 拖到槽且源在列表：源格将换成槽里那个动作
                readonly property var swapAction: (controller.dragOverSlot
                                                   && controller.dragIndex >= 0)
                    ? controller.rightSlot : null
                readonly property bool normalDrop: controller.ghostAction !== null
                    && (controller.dragTarget >= 0 || functionsArea.dropNoop)
                    && !controller.dragOverSlot && !controller.dragOverBar

                active: swapAction !== null || normalDrop
                action: swapAction !== null ? swapAction : controller.ghostAction
                label: action ? controller.tr(action.label) : ""
                x: (functionsArea.ghostPlaceIndex % functionsArea.columns)
                   * (functionsArea.cellW + controller.gap)
                y: Math.floor(functionsArea.ghostPlaceIndex / functionsArea.columns)
                   * (controller.keyH + controller.gap)
                width: functionsArea.cellW
                height: controller.keyH
                z: 60
            }

            // 挤出幽灵：拖进固定栏且满了，固定栏末尾那个动作会回到列表第一个
            GhostBlock {
                id: ejectedGhost
                action: controller.listEjected
                label: controller.listEjected ? controller.tr(controller.listEjected.label) : ""
                x: 0
                y: 0
                width: functionsArea.cellW
                height: controller.keyH
                z: 55
            }

            Repeater {
                id: cellRepeater
// 必须是真实数组：model 一换就销毁重建 delegate，拖动手势会断
                model: controller.availableActions || []

                delegate: Rectangle {
                    id: listCell
                    required property var modelData
                    required property int index
                    // 把点击入口暴露给 functionsArea（模拟点击用）
                    property alias cellMouse: cellMouse

                    readonly property bool isDragging: controller.editing
                                                      && controller.dragIndex === index
                    readonly property real cellW: functionsArea.cellW
                    // 动作状态：active 主题色底 / default 普通 / disabled 半透明
                    // 状态判断收在卡片里（actionStateOf），列表和固定栏共用
                    readonly property string actState: controller.actionStates[modelData.id] || "default"
                    // 拖动时这一格的让位偏移（纯计算，见 actions.js 的 listShift）
                    readonly property int shift: Actions.listShift({
                        index: index,
                        editing: controller.editing,
                        dragActive: controller.dragActive,
                        dragIndex: controller.dragIndex,
                        dragTarget: controller.dragTarget,
                        dropNoop: functionsArea.dropNoop,
                        insertAt: functionsArea.slotInsertIndex
                    })
                    // 拖进固定栏且挤出时，首位让给被挤出的动作
                    readonly property int barShift: Actions.listBarShift({
                        hasBarPlan: controller.barDropPlan !== null,
                        hasEjected: controller.listEjected !== null
                    })
                    readonly property int placed: index + shift + barShift
                    x: (placed % functionsArea.columns) * (cellW + controller.gap)
                    y: Math.floor(placed / functionsArea.columns) * (controller.keyH + controller.gap)
                    Behavior on x {
                        enabled: controller ? controller.animateCells : true
                        NumberAnimation { duration: Motion.listShift; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: controller ? controller.animateCells : true
                        NumberAnimation { duration: Motion.listShift; easing.type: Easing.OutCubic }
                    }
                    z: 1
                    // 拖动时原格子隐去，由跟手的 ghost 代表；禁用 50% / 按键透明度照样相乘
                    opacity: (isDragging ? 0 : 1)
                             * (actState === "disabled" ? 0.5 : 1)
                             * controller.keyOpacity
                    width: cellW
                    height: controller.keyH
                    radius: height / 2
                    // 激活态用和键帽「锁定」同一档：primary 实心 + onPrimary
                    color: actState === "active"
                           ? Theme.primary
                           : Theme.surfaceContainer

                    DRipple {
                        id: fnRipple
                        anchors.fill: parent
                        cornerRadius: parent.height / 2
                    }

                    // 左对齐横排：图标 │ 标题（与幽灵块同一份实现）
                    ActionLabel {
                        anchors.left: parent.left
                        anchors.leftMargin: Math.round(controller.keyH * 0.34)
                        anchors.verticalCenter: parent.verticalCenter
                        action: modelData
                        label: controller.tr(modelData.label)
                        color: actState === "active"
                               ? Theme.onPrimary
                               : Theme.withAlpha(controller.fg, 0.85)
                        iconSize: Math.round(controller.keyH * 0.42)
                        pixelSize: Math.max(12, Math.round(controller.keyH * 0.29))
                        dividerOpacity: actState === "active" ? 0.35 : 0.16
                        // 标题可用宽 = 磁贴宽 − 左右内边距 − 图标 − 间距 − 分隔线
                        readonly property real sidePad: Math.round(controller.keyH * 0.34)
                        maxLabelWidth: Math.max(24, parent.width - sidePad * 2
                            - Math.round(controller.keyH * 0.42) * 2 - 1)
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        enabled: !controller.editing && actState !== "disabled"
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        // 点击逻辑抽成函数：模拟点击和手指点走同一份
                        function tapAt() {
                            controller.quickAction(modelData.id)
                        }
                        onPressed: mouse => fnRipple.trigger(mouse.x, mouse.y)
                        onClicked: tapAt()
                    }

                    // 编辑态：长按拖动排序
                    DragInitiator {
                        id: cellDrag
                        enabled: controller.editing
                        controller: functionsArea.controller
                        owner: "cell"
                        ownerIndex: index
                        dragItem: listCell
                        payload: modelData
                        // 拖到可视区上/下边缘 → 设定滚动速度（越靠边越快）
                        onDragged: translation => {
                            // ghost 已经离开列表（拖去固定栏/槽）就别再滚了
                            if (!controller.ghostOverList) {
                                functionsArea.autoScrollSpeed = 0
                                return
                            }
                            const viewY = parent.y + parent.height / 2
                                        + translation.y - fnScroll.contentY
                            const edge = controller.keyH * 0.7
                            const maxSpeed = functionsArea.autoScrollMaxSpeed
                            let speed = 0
                            if (viewY < edge)
                                speed = -Math.min(1, (edge - viewY) / edge) * maxSpeed
                            else if (viewY > fnScroll.height - edge)
                                speed = Math.min(1, (viewY - (fnScroll.height - edge)) / edge) * maxSpeed
                            functionsArea.autoScrollSpeed = Math.round(speed)
                        }
                    }
                }
            }
        }
    }

    // 编辑态：列表外圈主题色边框
    Rectangle {
        opacity: (controller.editing ? 1 : 0) * (controller ? controller.bgOpacity : 1)
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
        }
        anchors.left: fnScroll.left
        anchors.right: fnScroll.right
        anchors.top: fnScroll.top
        anchors.bottom: fnScroll.bottom
        anchors.margins: -7
        radius: Theme.cornerRadius
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        z: 6
    }

    // 滚动区遮罩：贴在 Flickable 外沿，不随内容滚动
    Rectangle {
        anchors.left: fnScroll.left
        anchors.right: fnScroll.right
        anchors.bottom: fnScroll.bottom
        height: Math.round(controller.keyH * 0.7)
        z: 5
        opacity: (fnScroll.contentHeight > fnScroll.height + 1
                  && fnScroll.contentY < fnScroll.contentHeight - fnScroll.height - 1) ? 1 : 0
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.panel; easing.type: Easing.OutCubic }
        }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.0) }
            GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.94) }
        }
    }

    Rectangle {
        anchors.left: fnScroll.left
        anchors.right: fnScroll.right
        anchors.top: fnScroll.top
        height: Math.round(controller.keyH * 0.55)
        z: 5
        opacity: fnScroll.contentY > 1 ? 1 : 0
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.panel; easing.type: Easing.OutCubic }
        }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.94) }
            GradientStop { position: 1.0; color: Theme.withAlpha(Theme.surfaceContainer, 0.0) }
        }
    }

    // 底部一行：末尾的编辑按钮
    Item {
        id: fnFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: controller.keyH
        opacity: controller.editing ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.ghost; easing.type: Easing.OutCubic }
        }

        Rectangle {
            id: editBtn
            // 右边缘和功能列表对齐
            anchors.right: parent.right
            anchors.rightMargin: controller.unit / 2
            anchors.verticalCenter: parent.verticalCenter
            // 宽 2 个单位，高 2/3 个键高
            width: controller.unit * 2 + controller.gap
            height: Math.round(controller.keyH * 2 / 3)
            radius: height / 2
            // 和磁贴同一套填充（比磁贴深一档，读起来像「次级按钮」而不是另一个动作）
            color: Theme.surfaceContainerHigh

            DRipple {
                id: editRipple
                anchors.fill: parent
                cornerRadius: parent.height / 2
            }

            DIcon {
                anchors.centerIn: parent
                name: "edit"
                size: Math.round(controller.keyH * 0.42)
                color: Theme.withAlpha(controller.fg, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => editRipple.trigger(mouse.x, mouse.y)
                onClicked: controller.editing = true
            }
        }
    }

    // 模拟使用流程：点功能列表里的动作磁贴（按动作 id 找，见 scripts/acceptance.py）
    function pointerTapAction(actionId) {
        for (let i = 0; i < cellRepeater.count; i++) {
            const item = cellRepeater.itemAt(i)
            if (item && item.modelData && item.modelData.id === actionId && item.cellMouse) {
                item.cellMouse.tapAt()
                return true
            }
        }
        return false
    }
}
