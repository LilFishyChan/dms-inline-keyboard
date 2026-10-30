// 表情 / 符号页的主体：中间滚动网格 + 底部一行（返回 / 表情·符号切换 / 退格）。
// 顶部那行分类条是 EmojiCategoryBar（在 KeyboardCard 的 topArea 里）。
import QtQuick
import qs.Common
import qs.Widgets
import "layouts/emoji.js" as Emoji
import "Motion.js" as Motion
import qs.DCommon.Widgets

Item {
    id: panel

    // KeyboardCard 根
    property var controller: null

    // 符号页（± × ÷ § ¶）和表情页共用一个网格，但符号字形本身比 emoji
    // 高得多，用同一个缩放系数会显得过大，所以分开算
    readonly property bool isSymbolPage: controller.emojiSegment === "symbol"
    readonly property var groups: panel.isSymbolPage
                                  ? Emoji.symbolGroups : Emoji.emojiGroups

    // 当前分类的字符表；"all" = 该段所有分组顺次拼起来
    readonly property var items: {
        const list = panel.groups
        if (controller.emojiCategory === "all")
            return Emoji.flatten(list)
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === controller.emojiCategory)
                return list[i].items
        }
        return Emoji.flatten(list)
    }

    // 底部动作行高度 = 一个标准键高（退格要和键盘上的键一样好按）
    readonly property real actionH: controller.keyH
    readonly property real gap: controller.gap
    readonly property var backspaceKey: ({k: "key", c: 14, l: "Backspace"})

    // 列数按「一格大概 1.35 键高」推，窄键盘不至于挤成一排小点
    readonly property int columns: Math.max(6, Math.floor(width / (controller.keyH * 1.35)))

    Item {
        id: gridArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actionRow.top
        anchors.bottomMargin: panel.gap
        clip: true

        // 整行整行地摆：行数取整，避免最下面露出半行被裁
        readonly property int rows: Math.max(1, Math.round(height / (panel.controller.keyH + panel.gap)))
        readonly property real cellH: height / rows
        readonly property real cellW: width / panel.columns

        DGridView {
            id: grid
            anchors.fill: parent
            cellWidth: gridArea.cellW
            cellHeight: gridArea.cellH
            model: panel.items
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // 滑到分类末尾时不要出现「橡皮筋」回弹，平板上一弹就滑过头
            flickableDirection: Flickable.VerticalFlick

            delegate: Item {
                id: cell

                required property string modelData

                width: gridArea.cellW
                height: gridArea.cellH

                // 按下的高亮：用 TapHandler 的 pressed，MouseArea 会抢走
                // GridView 的拖动（滑不动列表）
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: Theme.cornerRadius
                    color: tap.pressed ? Theme.withAlpha(Theme.primary, 0.18)
                                       : "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: cell.modelData
                    // 表情字形本身有留白，乘 0.62 之后视觉大小才和键帽文字接近；
                    // 符号没有这层留白，同一系数会顶满格子，用小一号
                    font.pixelSize: Math.round(Math.min(cell.width, cell.height)
                                               * (panel.isSymbolPage ? 0.48 : 0.62))
                    color: panel.controller.fg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // 涟漪：由 TapHandler 的 pressed 驱动 —— 这里不能挂 MouseArea，
                // 那会抢走 GridView 的拖动，表情列表就滑不动了
                DRipple {
                    id: cellRipple
                    anchors.fill: parent
                    anchors.margins: 2
                    cornerRadius: Theme.cornerRadius
                }

                TapHandler {
                    id: tap
                    onTapped: panel.controller.textCommitRequested(cell.modelData)
                    onPressedChanged: {
                        // 圆心取当前触点：本机 Qt 版本里 centroid 恒为 null，只有 point 有效；
                        // 两个都拿不到就退回格子中心，至少还有涟漪
                        const p = tap.point ? tap.point.position : null
                        if (pressed) {
                            const pt = (p && !isNaN(p.x) && !isNaN(p.y))
                                       ? p : Qt.point(cell.width / 2, cell.height / 2)
                            cellRipple.trigger(pt.x, pt.y)
                        }
                    }
                }
            }
        }

        // 空分类兜底（数据表不该为空，但别让界面变成一片空白没人知道为什么）
        Text {
            anchors.centerIn: parent
            visible: panel.items.length === 0
            text: panel.controller.tr("Empty")
            color: Theme.withAlpha(panel.controller.fg, 0.45)
            font.pixelSize: Math.round(panel.controller.keyH * 0.4)
        }
    }

    Item {
        id: actionRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: panel.actionH

        readonly property real btnH: Math.round(height * 0.8)

        // 左：返回键盘
        Rectangle {
            id: backBtn
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(backLabel.implicitWidth + backIcon.width + height * 0.75)
            height: actionRow.btnH
            radius: height / 2
            color: backTap.pressed ? Theme.withAlpha(Theme.primary, 0.18)
                                   : Theme.surfaceContainer

            DIcon {
                id: backIcon
                anchors.left: parent.left
                anchors.leftMargin: Math.round(parent.height * 0.32)
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow_back"
                size: Math.round(parent.height * 0.5)
                color: Theme.withAlpha(panel.controller.fg, 0.85)
            }

            Text {
                id: backLabel
                anchors.left: backIcon.right
                anchors.leftMargin: Math.round(parent.height * 0.16)
                anchors.verticalCenter: parent.verticalCenter
                text: panel.controller.tr("Back")
                color: Theme.withAlpha(panel.controller.fg, 0.85)
                font.pixelSize: Math.round(parent.height * 0.34)
            }

            // 涟漪：和格子一样挂在 TapHandler 上（centroid 这版是 null，用 point）
            DRipple {
                id: backRipple
                anchors.fill: parent
                cornerRadius: height / 2
            }

            TapHandler {
                id: backTap
                onTapped: panel.controller.goPage("page1")
                onPressedChanged: {
                    if (pressed) {
                        const p = backTap.point ? backTap.point.position : null
                        backRipple.trigger(p && !isNaN(p.x) ? p.x : backBtn.width / 2,
                                         p && !isNaN(p.y) ? p.y : backBtn.height / 2)
                    }
                }
            }
        }

        // 中：表情 / 符号 切换（两段胶囊）
        Rectangle {
            id: segmentBox
            anchors.centerIn: parent
            height: actionRow.btnH
            width: segmentRow.width + Math.round(height * 0.16)
            radius: height / 2
            color: Theme.surfaceContainerHigh

            Row {
                id: segmentRow
                anchors.centerIn: parent
                spacing: Math.round(segmentBox.height * 0.08)

                Repeater {
                    model: [
                        {id: "emoji", label: panel.controller.tr("Emoji")},
                        {id: "symbol", label: panel.controller.tr("Symbols")}
                    ]

                    delegate: Rectangle {
                        required property var modelData

                        readonly property bool active:
                            panel.controller.emojiSegment === modelData.id

                        width: Math.round(segLabel.implicitWidth + segmentBox.height * 0.70)
                        height: Math.round(segmentBox.height * 0.82)
                        radius: height / 2
                        color: active ? Theme.primary : "transparent"
                        Behavior on color {
                            enabled: controller ? controller.animateCells : true
                            ColorAnimation { duration: Motion.micro }
                        }

                        Text {
                            id: segLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.active ? Theme.onPrimary
                                                 : Theme.withAlpha(panel.controller.fg, 0.85)
                            font.pixelSize: Math.round(segmentBox.height * 0.36)
                            font.weight: parent.active ? Font.DemiBold : Font.Normal
                        }

                        DRipple {
                            id: segRipple
                            anchors.fill: parent
                            cornerRadius: height / 2
                            rippleColor: active ? Theme.onPrimary : Theme.primary
                        }

                        TapHandler {
                            id: segTap
                            onTapped: {
                                if (panel.controller.emojiSegment === modelData.id)
                                    return
                                // 换段时分类回到「全部」：各段的分类 id 不是一套，
                                // 留着旧的会落到「找不到 → 回全部」的隐式兜底，不如显式清掉
                                panel.controller.emojiSegment = modelData.id
                                panel.controller.emojiCategory = "all"
                            }
                            onPressedChanged: {
                                if (pressed) {
                                    const p = segTap.point ? segTap.point.position : null
                                    const w = segLabel.width + segmentBox.height * 0.70
                                    segRipple.trigger(p && !isNaN(p.x) ? p.x : w / 2,
                                                    p && !isNaN(p.y) ? p.y : segmentBox.height * 0.41)
                                }
                            }
                        }
                    }
                }
            }
        }

        // 右：退格（长按连发）
        Rectangle {
            id: backspaceBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(actionRow.btnH * 1.5)
            height: actionRow.btnH
            radius: height / 2
            color: (bsTap.pressed || backRepeat.running)
                   ? Theme.withAlpha(Theme.primary, 0.18) : Theme.surfaceContainer

            DIcon {
                anchors.centerIn: parent
                name: "backspace"
                size: Math.round(parent.height * 0.5)
                color: Theme.withAlpha(panel.controller.fg, 0.85)
            }

            DRipple {
                id: bsRipple
                anchors.fill: parent
                cornerRadius: height / 2
            }

            TapHandler {
                id: bsTap
                onPressedChanged: {
                    if (pressed) {
                        const p = bsTap.point ? bsTap.point.position : null
                        bsRipple.trigger(p && !isNaN(p.x) ? p.x : backspaceBtn.width / 2,
                                       p && !isNaN(p.y) ? p.y : backspaceBtn.height / 2)
                        panel.didRepeat = false
                        backDelay.start()
                    } else {
                        backDelay.stop()
                        backRepeat.stop()
                    }
                }
                onTapped: if (!panel.didRepeat) panel.sendBackspace()
            }

            // 按住 400ms 后开始连发，60ms 一次
            Timer {
                id: backDelay
                interval: 400
                onTriggered: {
                    panel.didRepeat = true
                    panel.sendBackspace()
                    backRepeat.start()
                }
            }

            Timer {
                id: backRepeat
                interval: 60
                repeat: true
                onTriggered: panel.sendBackspace()
            }
        }
    }

    // 短按一次还是长按连发：长按照样会走 onTapped，用它去重
    property bool didRepeat: false

    function sendBackspace() {
        panel.controller.keyPressed(panel.backspaceKey)
    }
}
