// Inline Keyboard 的功能动作列表：4 行滚动网格 + 底部编辑按钮；
// 编辑态下可拖动排序、拖到顶部快捷栏/右上角槽。
// 拖动逻辑全部委托给 controller（= KeyboardCard 根），本文件负责布局与手势。
import QtQuick
import qs.Common
import qs.Widgets

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

    // 编辑态顶部空出的一行：拖动提示
    Item {
        id: editHint
        opacity: controller.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
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
        opacity: controller.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        anchors.left: fnScroll.left
        anchors.right: fnScroll.right
        y: fnScroll.y
        height: fnScroll.height
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerLow
    }

    Flickable {
        id: fnScroll
        // 左右各让出半个按键：列表宽度 = 键盘内容宽 - 1 个单位
        anchors.left: parent.left
        anchors.leftMargin: controller.unit / 2
        anchors.right: parent.right
        anchors.rightMargin: controller.unit / 2
        // 编辑态整体下移一行（带过渡）。这里只能用 y，不能同时设 anchors.top
        y: controller.editing ? controller.keyH : 0
        Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        height: functionsArea.scrollH
        clip: true
        contentHeight: fnGrid.height
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Item {
            id: fnGrid
            width: fnScroll.width
            height: Math.max(1, Math.ceil((controller.availableActions || []).length
                                          / functionsArea.columns))
                    * (controller.keyH + controller.gap) - controller.gap

            // 目标位置：松开后动作会落到这里（幽灵块样式，和固定栏一致）
            GhostBlock {
                id: dropShadow
                active: controller.ghostAction !== null && controller.dragTarget >= 0
                        && !controller.dragOverSlot && !controller.dragOverBar
                action: controller.ghostAction
                label: controller.ghostAction ? controller.tr(controller.ghostAction.label) : ""
                x: (controller.dragTarget % functionsArea.columns)
                   * (functionsArea.cellW + controller.gap)
                y: Math.floor(controller.dragTarget / functionsArea.columns)
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
                // ⚠ 必须是真实数组：model 一换就会销毁重建 delegate，拖动手势会断
                model: controller.availableActions || []

                delegate: Rectangle {
                    required property var modelData
                    required property int index

                    readonly property bool isDragging: controller.editing
                                                      && controller.dragIndex === index
                    // 拖进固定栏并且会挤出时，第一个位置让给幽灵块，整体后移一位
                    readonly property int barShift: (controller.barDropPlan !== null
                                                     && controller.listEjected !== null) ? 1 : 0
                    readonly property real cellW: functionsArea.cellW
                    // 动作状态：active 主题色底 / default 普通 / disabled 半透明
                    // 状态判断收在卡片里（actionStateOf），列表和固定栏共用
                    readonly property string actState: controller.actionStates[modelData.id] || "default"
                    // 拖动时其它格子的视觉让位（不改 model，避免打断拖动）
                    readonly property int shift: {
                        if (!controller.editing || !controller.dragActive)
                            return 0
                        // 拖出列表（去固定栏 / 槽）：源格之后整体前移一格，
                        // 源格自己已经 opacity 0，不能留一个空位
                        if (controller.dragIndex >= 0 && controller.dragTarget < 0)
                            return index > controller.dragIndex ? -1 : 0
                        if (controller.dragTarget < 0)
                            return 0
                        // 从快捷栏/槽拖进列表：没有源索引，target 之后的全部后移一位
                        if (controller.dragIndex < 0)
                            return index >= controller.dragTarget ? 1 : 0
                        if (index === controller.dragIndex)
                            return 0
                        if (controller.dragIndex < controller.dragTarget
                            && index > controller.dragIndex && index <= controller.dragTarget)
                            return -1
                        if (controller.dragIndex > controller.dragTarget
                            && index < controller.dragIndex && index >= controller.dragTarget)
                            return 1
                        return 0
                    }

                    readonly property int placed: index + shift + barShift
                    x: (placed % functionsArea.columns) * (cellW + controller.gap)
                    y: Math.floor(placed / functionsArea.columns)
                       * (controller.keyH + controller.gap)
                    Behavior on x {
                        enabled: controller.animateCells
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        enabled: controller.animateCells
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    // 拖动中的格子：抬高、半透明、跟手位移
                    z: isDragging ? 100 : 1
                    // 拖动时原格子隐去，由跟手的 ghost 代表；禁用 50% / 按键透明度照样相乘
                    opacity: (isDragging ? 0 : 1)
                             * (actState === "disabled" ? 0.5 : 1)
                             * controller.keyOpacity
                    scale: isDragging ? 1.04 : 1
                    Behavior on scale {
                        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }
                    width: cellW
                    height: controller.keyH
                    radius: height / 2
                    // 激活态用和键帽「锁定」同一档：primary 实心 + onPrimary
                    color: actState === "active"
                           ? Theme.primary
                           : Theme.surfaceContainer
                    // 平常不要边框；只有正被拖着的那一格用主题色描边
                    border.width: isDragging ? 1 : 0
                    border.color: Theme.primary

                    Ripple {
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
                        anchors.fill: parent
                        enabled: !controller.editing && actState !== "disabled"
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => fnRipple.press(mouse.x, mouse.y)
                        onReleased: fnRipple.release()
                        onCanceled: fnRipple.release()
                        onClicked: {
                            if (modelData.id === "opacity") {
                                // 快照由 daemon 在切模式时自己记：这里拿到的
                                // controller 是卡片，卡片上没有 prevBgOpacity，
                                // 直接写会抛 ReferenceError，后面切模式执行不到
                                controller.modeChangeRequested("transparency")
                                return
                            }
                            controller.quickAction(modelData.id)
                        }
                    }

                    // 编辑态：长按拖动排序
                    DragInitiator {
                        id: cellDrag
                        enabled: controller.editing
                        controller: functionsArea.controller
                        owner: "cell"
                        ownerIndex: index
                        payload: modelData
                        // 拖到可视区上/下边缘 → 设定滚动速度（越靠边越快）
                        onDragged: translation => {
                            // ghost 已经离开列表（拖去固定栏/槽）就别再滚了
                            if (!controller.ghostInList()) {
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
        opacity: controller.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
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
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
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
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

            Ripple {
                id: editRipple
                anchors.fill: parent
                cornerRadius: parent.height / 2
            }

            DankIcon {
                anchors.centerIn: parent
                name: "edit"
                size: Math.round(controller.keyH * 0.42)
                color: Theme.withAlpha(controller.fg, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => editRipple.press(mouse.x, mouse.y)
                onReleased: editRipple.release()
                onCanceled: editRipple.release()
                onClicked: controller.editing = true
            }
        }
    }
}
