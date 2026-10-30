// 表情 / 符号页的顶部分类条：全部 + 各分组。
// 高度和快捷栏相同（quickH），由 KeyboardCard 放在 topArea 里，替换掉快捷栏。
import QtQuick
import qs.Common
import "layouts/emoji.js" as Emoji
import "Motion.js" as Motion
import qs.DCommon.Widgets

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

    DFlickable {
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
                id: chipRepeater
                model: bar.chips

                delegate: Rectangle {
                    required property var modelData
                    // 把点击入口暴露给 bar（模拟点击用）
                    property alias chipTap: chipTap

                    readonly property bool active:
                        bar.controller.emojiCategory === modelData.id

                    width: Math.round(chipLabel.implicitWidth + height * 0.95)
                    height: Math.round(bar.height * 0.72)
                    y: (bar.height - height) / 2
                    radius: height / 2
                    color: active ? Theme.primary : Theme.surfaceContainer
                    Behavior on color {
                        enabled: controller ? controller.animateCells : true
                        ColorAnimation { duration: Motion.micro }
                    }

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        color: parent.active ? Theme.onPrimary : Theme.withAlpha(bar.controller.fg, 0.85)
                        font.pixelSize: Math.round(bar.height * 0.32)
                        font.weight: parent.active ? Font.DemiBold : Font.Normal
                    }

                    // 涟漪：同样挂在 TapHandler 上（它在横滑列表里才能既滚动又点击）
                    DRipple {
                        id: chipRipple
                        anchors.fill: parent
                        cornerRadius: height / 2
                        rippleColor: active ? Theme.onPrimary : Theme.primary
                    }

                    TapHandler {
                        id: chipTap
                        // 点击逻辑抽成函数：模拟点击和手指点走同一份
                        function tapAt() {
                            bar.controller.emojiCategory = modelData.id
                        }
                        onTapped: tapAt()
                        onPressedChanged: {
                            // 圆心取触点（centroid 在本机 Qt 版本里恒为 null，用 point）
                            const p = chipTap.point ? chipTap.point.position : null
                            if (pressed) {
                                const pt = (p && !isNaN(p.x) && !isNaN(p.y))
                                           ? p : Qt.point(chip.width / 2, chip.height / 2)
                                chipRipple.trigger(pt.x, pt.y)
                            }
                        }
                    }
                }
            }
        }
    }

    // 模拟使用流程：点分类条上的某个分组（见 scripts/acceptance.py）
    function pointerTapCategory(id) {
        for (let i = 0; i < chipRepeater.count; i++) {
            const item = chipRepeater.itemAt(i)
            if (item && item.modelData && item.modelData.id === id && item.chipTap) {
                item.chipTap.tapAt()
                return true
            }
        }
        return false
    }
}
