import QtQuick
import qs.Common
import qs.Widgets
import Qt5Compat.GraphicalEffects

// 统一的动作图标：同一个动作在任何位置（列表 / 快捷栏 / 右上角槽 / 拖动块）都长一样。
// icon 有两种写法：
//   - Material Symbols 名字（"undo"、"settings"…）→ DankIcon 字体图标
//   - 图片（".svg" / ".png" / "icons/x.svg" 相对插件目录 / "/abs/path" / "file://…"）→ Image + 着色
// 内置动作「悬浮」也走第二条：图标就是插件自带的 icons/keyboard-float.svg。
Item {
    id: root

    property var action: null
    property real size: 26
    property color color: Theme.surfaceText

    readonly property string iconName: action ? (action.icon || "") : ""

    // 图片图标：带图片扩展名、file:// 前缀或绝对路径
    readonly property bool isImageIcon: {
        const name = root.iconName
        if (name === "")
            return false
        if (name.indexOf("file://") === 0 || name.indexOf("/") === 0)
            return true
        return /\.(svg|png|jpe?g|webp)$/i.test(name)
    }
    // Image.source 需要 URL 或绝对路径
    readonly property string imageSource: {
        if (!root.isImageIcon)
            return ""
        const name = root.iconName
        if (name.indexOf("://") > 0 || name.indexOf("file:") === 0)
            return name
        if (name.indexOf("/") === 0)
            return "file://" + name
        // 相对路径按插件目录解析（icons/keyboard-float.svg）
        return Qt.resolvedUrl(name)
    }

    width: size
    height: size

    // 字体图标（Material Symbols）
    DankIcon {
        anchors.centerIn: parent
        visible: !root.isImageIcon
        name: root.iconName
        size: Math.round(root.size)
        color: root.color
    }

    // 自定义图片图标（SVG / PNG…），统一染成调用方给的颜色
    Image {
        anchors.centerIn: parent
        visible: root.isImageIcon
        source: root.imageSource
        sourceSize: Qt.size(Math.round(root.size), Math.round(root.size))
        width: root.size
        height: root.size
        fillMode: Image.PreserveAspectFit
        smooth: true
        layer.enabled: visible
        layer.effect: ColorOverlay {
            color: root.color
        }
    }

}
