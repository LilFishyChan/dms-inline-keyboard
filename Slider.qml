import QtQuick
import qs.Common

// 简易水平滑块：按住/拖动轨道改值
Item {
    id: root

    property real value: 1
    property real from: 0.1
    property real to: 1.0
    property color trackColor: Theme.withAlpha(Theme.surfaceText, 0.14)
    property color fillColor: Theme.primary
    readonly property real ratio: (value - from) / Math.max(0.0001, to - from)

    signal moved(real v)

    implicitHeight: Math.max(26, knob.height)

    function valueAt(px) {
        const r = Math.max(0, Math.min(1, px / Math.max(1, width)))
        return from + r * (to - from)
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: root.trackColor
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.ratio * parent.width)
        height: 6
        radius: 3
        color: root.fillColor
    }

    Rectangle {
        id: knob
        width: 22
        height: 22
        radius: 11
        color: root.fillColor
        x: Math.max(0, Math.min(parent.width - width, root.ratio * parent.width - width / 2))
        anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -8
        anchors.bottomMargin: -8
        onPressed: root.moved(root.valueAt(mouse.x))
        onPositionChanged: {
            if (pressed)
                root.moved(root.valueAt(mouse.x))
        }
    }
}
