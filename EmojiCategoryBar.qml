import "motion.js" as Motion
import "alpha.js" as Alpha
// 表情 / 符号页的顶部分类条：全部 + 各分组。
// 高度和快捷栏相同（quickH），由 KeyboardCard 放在 topArea 里，替换掉快捷栏。
import QtQuick
import "layouts/emoji.js" as Emoji
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets

Item {
    id: bar

    // KeyboardCard 根
    property var controller: null
    readonly property var groups: controller && controller.emojiSegment === "symbol" ? Emoji.symbolGroups : Emoji.emojiGroups
    // 「全部」排在最前面，默认选中它
    readonly property var chips: {
        const out = [{
            "id": "all",
            // chips 在初始化时就求值，那时 I18n 单例的 trFor 还没就绪，走卡片上的守卫版
            "label": controller.tr("All")
        }];
        for (let i = 0; i < groups.length; i++) out.push({
            "id": groups[i].id,
            "label": controller.tr(groups[i].label)
        })
        return out;
    }

    // 模拟点击分类：itemAt 在 Row 里不稳，按 id 直接落到 controller
    function pointerTapCategory(id) {
        for (let i = 0; i < bar.chips.length; i++) {
            if (bar.chips[i].id === id) {
                bar.controller.emojiCategory = id;
                return true;
            }
        }
        return false;
    }

    clip: true

    DFlickable {
        id: scroller

        anchors.fill: parent
        contentWidth: row.width
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Row {
            id: row

            height: scroller.height
            spacing: bar.controller.gap

            Repeater {
                id: chipRepeater

                model: bar.chips

                // MD3 过滤 chip：DButton 底层是 T.Button（TapHandler），和 Flickable 共存，横向滑动不会被吞
                delegate: DButton {
                    required property var modelData
                    readonly property bool active: bar.controller.emojiCategory === modelData.id

                    height: Math.round(bar.height * 0.72)
                    y: (bar.height - height) / 2
                    text: modelData.label
                    backgroundColor: active ? Theme.primary : Theme.chipSurface
                    textColor: active ? Theme.onPrimary : Theme.withAlpha(bar.controller.fg, Alpha.Bright)
                    onClicked: bar.controller.emojiCategory = modelData.id
                }

            }

        }

    }

}
