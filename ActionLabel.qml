// 动作的一行展示：图标 │ 分隔线 │ 标题。
// 列表磁贴、拖动落点幽灵、被挤出的幽灵都用它 —— 这三处本来各写了一份，
// 其中一份已经漏了分隔线，抽出来才不会继续漂移。
import QtQuick
import qs.Common
import qs.Widgets

Row {
    id: root

    property var action: null
    // 已经翻译好的标题；空串表示只显示图标
    property string label: ""
    property color color: Theme.surfaceText
    property int iconSize: 18
    property int pixelSize: 14
    // 分隔线的不透明度：磁贴用 0.16/0.35，幽灵块用 0.45
    property real dividerOpacity: 0.45
    // 标题可用宽度上限；<=0 表示不限制（浮在列表外的幽灵块没有容器宽度）
    property real maxLabelWidth: -1

    spacing: Math.round(iconSize * 0.43)

    ActionIcon {
        anchors.verticalCenter: parent.verticalCenter
        action: root.action
        size: root.iconSize
        color: root.color
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        width: 1
        height: Math.round(root.iconSize * 1.29)
        color: root.color
        opacity: root.dividerOpacity
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        // 行高跟着图标走，文字在行内垂直居中。
        // 只靠 anchors.verticalCenter 时，HorizontalFit 缩小字号后会按
        // 原字号算行高，基线偏下 —— 看着就是"没垂直居中"。
        height: root.iconSize
        verticalAlignment: Text.AlignVCenter
        text: root.label
        color: root.color
        // 给了上限就按宽度自适应字号，保证一行放得下、不溢出
        width: root.maxLabelWidth > 0 ? root.maxLabelWidth : implicitWidth
        elide: Text.ElideNone
        wrapMode: Text.NoWrap
        fontSizeMode: root.maxLabelWidth > 0 ? Text.HorizontalFit : Text.FixedSize
        minimumPixelSize: 8
        font.pixelSize: root.pixelSize
    }
}
