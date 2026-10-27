// Inline Keyboard 底部把手行：左侧收起键、中间「拼」/输入法状态、右侧 fcitx5 托盘图标。
// 高度是半个标准键高；图标裸画不加深色底块。由 KeyboardCard 实例化。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: handleBar

    property var controller: null
    width: parent.width
    height: controller.handleH
    visible: controller.showHandle

    // 中间拖动把手的外观（宽度固定，高度按键高的比例）
    readonly property real gripWidth: 76
    readonly property real gripHeightRatio: 0.12

    // 左端：收起
    DankIcon {
        id: hideBtn
        anchors.left: parent.left
        anchors.leftMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        name: "expand_more"
        size: Math.round(controller.handleH * 0.92)
        color: Theme.withAlpha(controller.fg, 0.72)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: controller.quickAction("close")
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

    // 右端：地球 —— 点击切换输入法
    DankIcon {
        id: langBtn
        anchors.right: parent.right
        anchors.rightMargin: controller.pad
        anchors.verticalCenter: parent.verticalCenter
        name: "language"
        size: Math.round(controller.handleH * 0.92)
        color: Theme.withAlpha(controller.fg, 0.72)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            // 单击：在本列表里循环切到下一项（含 rime 中英文态）
            onClicked: {
                controller.imListRequested()
                controller.imCycleRequested()
            }
            onPressAndHold: {
                controller.imListRequested()
                controller.imPickerOpen = true
            }
        }
    }
}
