// 展开的候选列表页。
//
// 点顶栏的 ⌄ 不是弹浮层，而是把整块键区换成一页候选：
//   左区：候选词自动换行排列（Flow），不规定每行几个
//   右区：一列按钮 ─ ↑ 上翻 / ↓ 下翻 /（空一格）/ ⌫ 退格 / ↵ 回车
//
// 候选词样式和顶部候选栏完全一致：容器左右内边距各 ⅓ 键宽、
// 容器间距 = 键间距（gap）、分隔线画在间距正中间。两处用的是同一套度量。
//
// 几何按 Column 的排布算出来：不能用 anchors.top + topMargin 猜，
// 因为 mainArea 隐藏后 Column 不再为它留位，锚点会算错。
import QtQuick
import qs.Common
import qs.Widgets

Rectangle {
    id: panel

    // 卡片实例：候选数据、键高等全从它读
    required property var controller

    readonly property var c: controller

    // 和主键盘一致的度量
    readonly property real unit: c.unit || 63
    readonly property real gap: c.gap || 6

    // 一个标准键宽：主区按 14 个键位切（B 行 13 键 + 双宽 Backspace）
    readonly property real slotW: Math.max(1, Math.floor(width / 14))
    readonly property real rowH: c.keyH
    readonly property int rowCount: 5

    // 卡片内容区宽度。这里必须用它而不是 width ——
    // width 是下面那行绑定的，初始化那一刻还是 0（踩过）。
    readonly property real panelWidth: c.width - c.pad * 2

    x: c.pad
    y: c.pad + Math.max(c.quickH, c.candH) + c.gap
    width: panelWidth
    // 5 行，每行一个键高：和键区完全同高
    height: rowCount * rowH + (rowCount - 1) * gap

    visible: c.candExpanded && c.showCandBar && c.candOverflow
    z: 50
    radius: Theme.cornerRadius
    color: Theme.surface

    // 候选栏已经显示过的那几个要跳过，列表从这里接着排。
    // 跳过数量用「候选栏实际放下几个」（candFitCount），不是候选总数。
    //
    // 全量还没到的时候**不能**跳过：那时手上只有 addon 的当前页，
    // 跳过 6 个就什么都不剩了 —— 展开面板一片空白就是这么来的。
    readonly property bool hasFullList: c.allCandidates.length > 0
    readonly property var pageModel: {
        const all = hasFullList ? c.allCandidates : c.candidates
        if (all.length === 0)
            return []
        if (!hasFullList)
            return all
        const skip = c.candFitCount || 0
        return all.length > skip ? all.slice(skip) : all
    }

    // ---- 翻页：一屏算一页 ----
    // Flow 是连续流，没有天然的页边界，所以按可视高度翻。
    property int pageIndex: 0
    readonly property int pageCount:
        Math.max(1, Math.ceil(flow.height / Math.max(1, view.height)))
    onPageCountChanged: if (pageIndex > pageCount - 1) pageIndex = pageCount - 1

    function prevPage() {
        if (pageIndex > 0)
            pageIndex--
        applyScroll()
    }

    function nextPage() {
        if (pageIndex < pageCount - 1)
            pageIndex++
        applyScroll()
    }

    function applyScroll() {
        const maxY = Math.max(0, flow.height - view.height)
        view.contentY = Math.min(maxY, pageIndex * view.height)
    }

    // 列表从候选栏之后开始，选词要把跳过的偏移补回来。
    // 全量还没到时不跳过，也就不加偏移。
    function choose(index) {
        const skip = hasFullList ? (c.candFitCount || 0) : 0
        c.selectCandidate(index + skip)
        c.candExpanded = false
    }

    // ---- 左区：候选词自动换行 ----

    Flickable {
        id: view

        x: 8
        y: 0
        width: panel.width - panel.slotW - 16
        height: panel.height
        clip: true

        contentWidth: width
        contentHeight: flow.height
        boundsBehavior: Flickable.StopAtBounds

        Flow {
            id: flow

            width: view.width
            spacing: panel.gap

            Repeater {
                model: panel.pageModel

                delegate: Item {
                    required property int index
                    required property var modelData

                    // 容器宽 = 文字 + 左右各 ⅓ 键宽；高 = 一个键高
                    width: cellText.implicitWidth + panel.unit * 2 / 3
                    height: panel.rowH

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 7
                        color: cellMouse.containsMouse
                               ? Theme.withAlpha(Theme.primary, 0.16)
                               : "transparent"
                    }

                    Text {
                        id: cellText
                        anchors.centerIn: parent
                        text: String(modelData ?? "")
                        color: panel.c.fg
                        font.pixelSize: Math.round(panel.rowH * 0.42)
                        font.weight: Font.Normal
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: panel.choose(index)
                    }

                    // 分隔线画在间距正中间，最后一项不画
                    Rectangle {
                        visible: index < panel.pageModel.length - 1
                        x: parent.width + Math.round(panel.gap / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Math.round(panel.rowH * 0.5)
                        color: Theme.withAlpha(panel.c.fg, 0.3)
                    }
                }
            }
        }
    }

    // ---- 右区：一列按钮 ----

    Column {
        id: sideButtons

        anchors.right: parent.right
        width: panel.slotW
        height: panel.height

        Repeater {
            model: panel.rowCount

            delegate: Item {
                required property int index

                width: sideButtons.width
                height: panel.rowH

                // 第 3 格（index 2）是空行，隔开翻页和编辑键
                readonly property bool blank: index === 2

                // 外观和主键盘功能键一致：surfaceContainer 底、
                // surfaceText 字、Medium 字重、0.32 倍键高（Key.qml 的 mainLabelRatio）
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: Math.round(panel.rowH * 0.18)
                    visible: !parent.blank
                    color: sideMouse.containsMouse
                           ? Theme.surfaceContainerHighest
                           : Theme.surfaceContainer
                }

                Text {
                    anchors.centerIn: parent
                    visible: !parent.blank
                    text: index === 0 ? "\u2191"
                        : index === 1 ? "\u2193"
                        : index === 3 ? "\u232b"
                        : index === 4 ? "\u21b5" : ""
                    color: Theme.surfaceText
                    font.pixelSize: Math.round(panel.rowH * 0.32)
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: sideMouse
                    anchors.fill: parent
                    enabled: !parent.blank
                    hoverEnabled: true
                    onClicked: {
                        if (index === 0) {
                            panel.prevPage()
                        } else if (index === 1) {
                            panel.nextPage()
                        } else if (index === 3) {
                            panel.c.keyPressed({ k: "key", l: "Backspace", c: 14 })
                        } else if (index === 4) {
                            panel.c.keyPressed({ k: "key", l: "Enter", c: 28 })
                        }
                    }
                }
            }
        }
    }

    // 右上角收起
    Rectangle {
        id: collapseButton

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 5
        width: Math.round(panel.rowH * 0.46)
        height: width
        radius: width / 2
        color: collapseMouse.containsMouse
               ? Theme.withAlpha(Theme.primary, 0.24)
               : Theme.surfaceContainerHigh
        z: 10

        Text {
            anchors.centerIn: parent
            text: "\u2303"
            color: panel.c.fg
            font.pixelSize: Math.round(parent.width * 0.55)
        }

        MouseArea {
            id: collapseMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: panel.c.candExpanded = false
        }
    }
}
