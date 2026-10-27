// 拖动中的跟手块：圆形主题色底 + 动作图标。
// 必须是卡片的直接子项（不能放进列表里）：列表的 clip 会把它正好在最需要时裁掉。
// 拖到固定栏 / 动作槽上时不再淡化：落点由那里的幽灵块表示，跟手块保持实心，
// 免得两个都变半透明反而看不清拖的是什么。
import QtQuick
import qs.Common

Rectangle {
    id: root

    property var controller: null

    visible: root.controller.editing && root.controller.ghostAction !== null
    opacity: root.controller.ghostFading ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    z: 300
    width: root.controller.keyH
    height: root.controller.keyH
    radius: width / 2
    color: Theme.withAlpha(Theme.primary, 0.92)
    x: root.controller.ghostX - width / 2
    y: root.controller.ghostY - height / 2

    ActionIcon {
        anchors.centerIn: parent
        action: root.controller.ghostAction
        size: Math.round(parent.width * 0.45)
        color: Theme.onPrimary
    }
}
