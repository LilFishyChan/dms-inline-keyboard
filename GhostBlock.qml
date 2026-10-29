// 落点幽灵块：半透明 + 主题色描边，表示「松手之后这个动作会在这里」。
// 固定栏的插入位、列表的落点、被挤出到列表首位的动作，共用这一套样式。
// 尺寸由使用方给（宽度/高度各自不同），这里只管画。
import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: root

    property var action: null
    // 已经翻译好的标题；空串 = 只画居中的图标（固定栏那种窄块）
    property string label: ""
    // 额外的显示条件（比如「只在拖动到列表落点时才显示」）
    property bool active: true
    // 只有图标时，图标占块高的比例（固定栏的块比图标行窄，用 0.6 才对得上真实块）
    property real iconRatio: 0.5

    readonly property bool hasLabel: label !== ""
    readonly property int iconSize: hasLabel
        ? Math.round(height * 0.42) : Math.round(height * iconRatio)

    visible: active && action !== null
    opacity: action !== null ? 0.55 : 0
    radius: height / 2
    // 比编辑态背景（surfaceContainerLow）亮一档，否则和背景完全同色、只剩一个淡框
    color: Theme.surface
    border.width: 2
    border.color: Theme.primary

    ActionLabel {
        visible: root.hasLabel
        anchors.left: parent.left
        anchors.leftMargin: Math.round(root.height * 0.34)
        anchors.verticalCenter: parent.verticalCenter
        action: root.action
        label: root.label
        color: Theme.primary
        iconSize: root.iconSize
        pixelSize: Math.max(12, Math.round(root.height * 0.29))
        // 不给上限时 ActionLabel 用 implicitWidth，elide 又是 ElideNone，
        // 名字一长就直接冲出幽灵块右边界。给宽后它自动切 HorizontalFit。
        // 可用宽 = 块宽 − 左内边距 − 图标 − 图标右侧留白
        maxLabelWidth: Math.max(24, root.width
                                - Math.round(root.height * 0.34) * 2
                                - root.iconSize * 2 - 1)
        dividerOpacity: 0.45
    }

    ActionIcon {
        visible: !root.hasLabel
        anchors.centerIn: parent
        action: root.action
        size: root.iconSize
        color: Theme.primary
    }
}
