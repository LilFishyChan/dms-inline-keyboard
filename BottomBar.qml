// Inline Keyboard 底部把手行：左侧收起键、中间「拼」/输入法状态、右侧 fcitx5 托盘图标。
// 高度是半个标准键高；图标裸画不加深色底块。由 KeyboardCard 实例化。
import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets

Item {
    id: handleBar

    property var controller: null
    width: parent.width
    height: controller.handleH
    visible: controller.showHandle

    // 中间拖动把手的外观。宽度跟随把手行高度（≈2.6 倍），
    // 键盘尺寸变化时比例不变；原来写死 76 在窄键盘上显得短。
    readonly property real gripWidth: Math.round(controller.handleH * 2.6)
    readonly property real gripHeightRatio: 0.12

    // 两端的圆形按钮尺寸：和顶部动作栏固定按钮同一套比例
    readonly property real endBtn: Math.round(controller.handleH * 0.86)
    readonly property real endIcon: Math.round(controller.handleH * 0.5)

    // 左端：收起。圆形触控区，背景透明、图标用正文色，
    // 和底部整行的观感一致（不额外压一个色块）。
    Rectangle {
        id: hideBtn
        anchors.left: parent.left
        anchors.leftMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        width: handleBar.endBtn
        height: handleBar.endBtn
        radius: width / 2
        color: "transparent"

        DIcon {
            anchors.centerIn: parent
            name: "expand_more"
            size: handleBar.endIcon
            color: controller.fg
        }

        DRipple {
            id: hideRipple
            anchors.fill: parent
            cornerRadius: width / 2
        }

        MouseArea {
            id: hideMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            function tapAt() {
                controller.quickAction("close")
            }
            onPressed: mouse => hideRipple.trigger(mouse.x, mouse.y)
            onClicked: tapAt()
        }
    }

    // 中间：拖动把手（仅浮动模式）
    Rectangle {
        id: grip
        visible: controller.dragEnabled
        anchors.centerIn: parent
        width: handleBar.gripWidth
        height: Math.max(3, controller.handleH * handleBar.gripHeightRatio)
        radius: height / 2
        color: Theme.withAlpha(controller.fg, 0.5)
    }

    // 拖动区：整条把手（两端图标除外）
    Item {
        id: dragArea
        anchors.left: hideBtn.right
        anchors.right: langBtn.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: controller.dragEnabled

        DragHandler {
            target: null
            onActiveChanged: if (active) controller.dragStarted()
            onTranslationChanged: controller.dragMoved(translation.x, translation.y)
        }
    }

    // 右端：地球 —— 点击切换输入法。样式同左端。
    Rectangle {
        id: langBtn
        anchors.right: parent.right
        anchors.rightMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        width: handleBar.endBtn
        height: handleBar.endBtn
        radius: width / 2
        color: "transparent"

        DIcon {
            anchors.centerIn: parent
            name: "language"
            size: handleBar.endIcon
            color: controller.fg
        }

        DRipple {
            id: langRipple
            anchors.fill: parent
            cornerRadius: width / 2
        }

        MouseArea {
            id: langMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            // 单击逻辑抽成函数：模拟点击和手指点走同一份
            function tapAt() {
                controller.imListRequested()
                controller.imCycleRequested()
            }
            onPressed: mouse => langRipple.trigger(mouse.x, mouse.y)
            // 单击：在本列表里循环切到下一项（含 rime 中英文态）
            onClicked: tapAt()
            onPressAndHold: {
                controller.imListRequested()
                controller.imPickerOpen = true
            }
        }
    }

    // 模拟使用流程：底部两个按钮（close = 关闭键盘 / lang = 地球键）
    function pointerTap(which) {
        if (which === "close") {
            hideMouse.tapAt()
            return true
        }
        if (which === "lang") {
            langMouse.tapAt()
            return true
        }
        return false
    }
}
