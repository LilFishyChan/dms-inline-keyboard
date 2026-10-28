// 表情 / 符号页的顶部分类条：全部 + 各分组。
// 高度和快捷栏相同（quickH），由 KeyboardCard 放在 topArea 里，替换掉快捷栏。
// 只负责「有哪些分类、当前选哪个」，选中值写回卡片（emojiCategory），
// 内容由 EmojiPanel 读同一份状态 —— 两边不同源会立刻错位。
import QtQuick
import qs.Common
import "layouts/emoji.js" as Emoji

Item {
    id: bar

    // KeyboardCard 根
    property var controller: null

    readonly property var groups: controller && controller.emojiSegment === "symbol"
                                  ? Emoji.symbolGroups : Emoji.emojiGroups

    // 「全部」排在最前面，默认选中它
    readonly property var chips: {
        const out = [{id: "all", label: controller.tr("All")}]
        for (let i = 0; i < groups.length; i++)
            out.push({id: groups[i].id, label: controller.tr(groups[i].label)})
        return out
    }

    clip: true

    Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: row.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // 窄屏 / 分类多的时候要能横向滑，但单个分类条目的点击不能被拖动吞掉：
        // 用 TapHandler 而不是 MouseArea（TapHandler 会和 Flickable 共存）
        Row {
            id: row
            height: scroller.height
            spacing: bar.controller.gap

            Repeater {
                model: bar.chips

                delegate: Rectangle {
                    required property var modelData

                    readonly property bool active:
                        bar.controller.emojiCategory === modelData.id

                    width: Math.round(chipLabel.implicitWidth + height * 0.95)
                    height: Math.round(bar.height * 0.72)
                    y: (bar.height - height) / 2
                    radius: height / 2
                    color: active ? Theme.primary : Theme.surfaceContainer
                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.active ? Theme.onPrimary : Theme.withAlpha(bar.controller.fg, 0.85)
                        font.pixelSize: Math.round(bar.height * 0.32)
                        font.weight: parent.active ? Font.DemiBold : Font.Normal
                    }

                    TapHandler {
                        onTapped: bar.controller.emojiCategory = modelData.id
                    }
                }
            }
        }
    }
}
