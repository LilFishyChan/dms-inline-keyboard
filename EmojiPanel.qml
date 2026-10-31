import "Motion.js" as Motion
// 表情 / 符号页的主体：中间滚动网格 + 底部一行（返回 / 表情·符号切换 / 退格）。
// 顶部那行分类条是 EmojiCategoryBar（在 KeyboardCard 的 topArea 里）。
import QtQuick
import "layouts/emoji.js" as Emoji
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    id: panel

    // KeyboardCard 根
    property var controller: null
    // 分段按钮的当前索引（和 controller.emojiSegment 双向同步，给诊断和验收用）
    readonly property int segmentIndex: segmentGroup.currentIndex
    // 符号页（± × ÷ § ¶）和表情页共用一个网格，但符号字形本身比 emoji
    // 高得多，用同一个缩放系数会显得过大，所以分开算
    readonly property bool isSymbolPage: controller.emojiSegment === "symbol"
    readonly property var groups: panel.isSymbolPage ? Emoji.symbolGroups : Emoji.emojiGroups
    // 当前分类的字符表；"all" = 该段所有分组顺次拼起来
    readonly property var items: {
        const list = panel.groups;
        if (controller.emojiCategory === "all")
            return Emoji.flatten(list);

        for (let i = 0; i < list.length; i++) {
            if (list[i].id === controller.emojiCategory)
                return list[i].items;

        }
        return Emoji.flatten(list);
    }
    // 底部动作行高度 = 一个标准键高（退格要和键盘上的键一样好按）
    readonly property real actionH: controller.keyH
    readonly property real gap: controller.gap
    readonly property var backspaceKey: ({
        "k": "key",
        "c": 14,
        "l": "Backspace"
    })
    // 列数按「一格大概 1.35 键高」推，窄键盘不至于挤成一排小点
    readonly property int columns: Math.max(6, Math.floor(width / (controller.keyH * 1.35)))
    // 短按一次还是长按连发：长按照样会走 onTapped，用它去重
    property bool didRepeat: false

    // 模拟点分段按钮（走 DButtonGroup 自己的 selectItem，和手指点同一条路径）
    function pointerTapSegment(index) {
        if (!segmentGroup || index < 0)
            return false;

        segmentGroup.selectItem(index);
        return true;
    }

    function sendBackspace() {
        panel.controller.keyPressed(panel.backspaceKey);
    }

    Item {
        id: gridArea

        // 整行整行地摆：行数取整，避免最下面露出半行被裁
        readonly property int rows: Math.max(1, Math.round(height / (panel.controller.keyH + panel.gap)))
        readonly property real cellH: height / rows
        readonly property real cellW: width / panel.columns

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actionRow.top
        anchors.bottomMargin: panel.gap
        clip: true

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
                    color: tap.pressed ? Theme.withAlpha(Theme.primary, 0.18) : "transparent"
                }

                StyledText {
                    anchors.centerIn: parent
                    text: cell.modelData
                    // 表情字形本身有留白，乘 0.62 之后视觉大小才和键帽文字接近；
                    // 符号没有这层留白，同一系数会顶满格子，用小一号
                    font.pixelSize: Math.round(Math.min(cell.width, cell.height) * (panel.isSymbolPage ? 0.48 : 0.62))
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
                        const p = tap.point ? tap.point.position : null;
                        if (pressed) {
                            const pt = (p && !isNaN(p.x) && !isNaN(p.y)) ? p : Qt.point(cell.width / 2, cell.height / 2);
                            cellRipple.trigger(pt.x, pt.y);
                        }
                    }
                }

            }

        }

        // 空分类兜底（数据表不该为空，但别让界面变成一片空白没人知道为什么）
        StyledText {
            anchors.centerIn: parent
            visible: panel.items.length === 0
            text: panel.controller.tr("Empty")
            color: Theme.withAlpha(panel.controller.fg, 0.45)
            font.pixelSize: Math.round(panel.controller.keyH * 0.4)
        }

    }

    Item {
        id: actionRow

        readonly property real btnH: Math.round(height * 0.8)

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: panel.actionH

        // 左：返回键盘（官方按钮，自带涟漪和焦点）
        DButton {
            id: backBtn

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: actionRow.btnH
            text: panel.controller.tr("Back")
            iconName: "arrow_back"
            onClicked: panel.controller.goPage("page1")
        }

        // 中：表情 / 符号 切换（官方分段控件）
        DButtonGroup {
            id: segmentGroup

            // controller 是唯一真源，按钮索引单向跟随
            function syncFromController() {
                const idx = panel.controller.emojiSegment === "emoji" ? 0 : 1;
                if (currentIndex !== idx)
                    currentIndex = idx;

            }

            anchors.centerIn: parent
            model: [panel.controller.tr("Emoji"), panel.controller.tr("Symbols")]
            selectionMode: "single"
            // DButtonGroup 单选只发 selectionChanged，不会自己改 currentIndex
            currentIndex: -1
            onSelectionChanged: (index, selected) => {
                if (!selected)
                    return ;

                currentIndex = index;
                const id = index === 0 ? "emoji" : "symbol";
                if (panel.controller.emojiSegment === id)
                    return ;

                // 换段时分类回到「全部」：各段的分类 id 不是一套
                panel.controller.emojiSegment = id;
                panel.controller.emojiCategory = "all";
            }
            Component.onCompleted: syncFromController()

            Connections {
                function onEmojiSegmentChanged() {
                    segmentGroup.syncFromController();
                }

                target: panel.controller
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
            color: (bsTap.pressed || backRepeat.running) ? Theme.withAlpha(Theme.primary, 0.18) : Theme.surfaceContainer

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
                        const p = bsTap.point ? bsTap.point.position : null;
                        bsRipple.trigger(p && !isNaN(p.x) ? p.x : backspaceBtn.width / 2, p && !isNaN(p.y) ? p.y : backspaceBtn.height / 2);
                        panel.didRepeat = false;
                        backDelay.start();
                    } else {
                        backDelay.stop();
                        backRepeat.stop();
                    }
                }
                onTapped: {
                    if (!panel.didRepeat)
                        panel.sendBackspace();

                }
            }

            // 按住 400ms 后开始连发，60ms 一次
            Timer {
                id: backDelay

                interval: 400
                onTriggered: {
                    panel.didRepeat = true;
                    panel.sendBackspace();
                    backRepeat.start();
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

}
