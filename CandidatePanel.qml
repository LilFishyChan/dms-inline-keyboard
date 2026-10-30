// 候选词列表页：覆盖键盘按键区，把候选摊开。
// 左侧 DListView 按行虚拟化（右侧一列是翻页/退格键）。

import QtQuick
import qs.Common
import qs.Widgets
import "Motion.js" as Motion
import "candidates.js" as Candidates
import qs.DCommon.Widgets

Item {
    id: candList

    property var controller: null

    // 度量全部来自卡片（controller 就是 KeyboardCard）
    readonly property real unit: controller.unit || 63
    readonly property real keyH: controller.keyH || 64
    readonly property real gap: controller.gap || 6
    readonly property int rowCount: controller.keyRowCount || 5

    // 跟按键主标签的比例走（Key.qml mainLabelRatio），和顶部候选栏保持一致
    readonly property int candFontSize: Math.round(keyH * 0.32)
    readonly property real rowH: Math.max(keyH * 0.72, candFontSize * 1.5)

    readonly property real colW: unit
    // 滚动条往左让出的宽度；换行也读 listW，避免文字被滚动条压住
    readonly property real scrollGutter: 10
    readonly property real listW: Math.max(0, width - colW - gap - scrollGutter)
    readonly property real areaH: rowCount * keyH + Math.max(0, rowCount - 1) * gap

    // 收起时由 KeyboardCard 置 0，让布局清空、不再持有渲染对象
    property int shownCountOverride: -1
    readonly property bool active: shownCountOverride !== 0

    // controller 构造期可能为 null，取它的地方都要兜底
    readonly property color fgColor: controller ? controller.fg : Theme.surfaceText

    width: parent ? parent.width : 0
    height: areaH

    // 布局缓存：每个元素 { x, y, w, t, i, sep }
    //   sep = 这一项右边要不要画分隔线（行内非末项才画）
    property var items: []
    // 按行分组，作为 DListView 的 model
    property var rows: []
    property real contentH: 0

    TextMetrics {
        id: measure
        font.pixelSize: candList.candFontSize
        font.weight: Font.Normal
    }

    // 测宽：TextMetrics 得先改 text 再读 advanceWidth
    function measureWidth(t) {
        measure.text = t
        return measure.advanceWidth
    }

    // 分行与宽度分配在 candidates.js（纯函数，有单测）
    function rebuildLayout() {
        if (!active || !controller) {
            items = []
            rows = []
            contentH = 0
            return
        }
        const laid = Candidates.layoutCandidates(controller.candListSlice, measureWidth, {
            availW: listW,
            gap: gap,
            rowH: rowH,
            pad: unit * 2 / 3
        })
        items = laid.items
        rows = laid.rows
        contentH = laid.contentH
    }

    // 结构类变化（尺寸、开关）立刻重排：这些不是高频事件，
    // 而且等着 debounce 会让面板在展开瞬间短暂空白。
    onControllerChanged: rebuildLayout()
    onWidthChanged: rebuildLayout()
    onUnitChanged: rebuildLayout()
    onGapChanged: rebuildLayout()
    onActiveChanged: rebuildLayout()
    onKeyHChanged: rebuildLayout()
    Component.onCompleted: rebuildLayout()

    // 候选数据变了就重排。candListSlice 是 property var，直接监听不可靠，
    // 用卡片给的 candRevision（int）当触发源。
    readonly property int relayoutInterval: 80
    property double lastRelayoutAt: 0

    Timer {
        id: relayoutTailTimer
        interval: candList.relayoutInterval
        repeat: false
        onTriggered: {
            candList.lastRelayoutAt = Date.now()
            candList.rebuildLayout()
        }
    }

    // 绕过节流，立刻重排。给「选词」这类明确动作专用：
    // 列表页本来就不会用来连续打字，没有合并的需要。
    function forceRelayout() {
        relayoutTailTimer.stop()
        candList.lastRelayoutAt = Date.now()
        candList.rebuildLayout()
    }

    // 立刻重排一次，或者排一次尾部补发
    function requestRelayout() {
        const now = Date.now()
        const elapsed = now - candList.lastRelayoutAt
        if (elapsed >= candList.relayoutInterval) {
            candList.lastRelayoutAt = now
            candList.rebuildLayout()
            // 刚重排过，已经排队的尾补发就没必要了
            relayoutTailTimer.stop()
        } else if (!relayoutTailTimer.running) {
            relayoutTailTimer.interval = candList.relayoutInterval - elapsed
            relayoutTailTimer.start()
        }
    }

    Connections {
        target: candList.controller
        ignoreUnknownSignals: true
        // candDataSeq 覆盖所有数据来源（真实推送 + 调试注入），
        // candRevision 只有推送路径才会动
        function onCandDataSeqChanged() {
            // 选词刚发生：列表页此时不会被用来连续打字，没有合并的需要，
            // 直接立刻重排（绕过节流）。否则 addon 回包后还要再等一个
            if (candList.controller && candList.controller.recentSelect)
                candList.forceRelayout()
            else
                candList.requestRelayout()
        }
    }

    // 左侧滚动区：virtual 化交给 DListView，一行一个 delegate
    DListView {
        id: candView

        anchors.left: parent.left
        anchors.top: parent.top
        width: candList.listW
        height: candList.areaH
        clip: true
        model: candList.rows
        spacing: candList.gap
        // 候选行是等分网格，边缘渐隐和逐行淡入都会让字看起来在闪
        fadeEdges: false
        rowFadeEnabled: false
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2400

        delegate: Item {
            id: rowItem

            required property var modelData

            readonly property var cells: modelData

            width: candView.width
            height: candList.rowH

            Repeater {
                model: rowItem.cells

                delegate: Item {
                    id: cell

                    required property var modelData

                    x: modelData.x
                    width: modelData.w
                    height: rowItem.height

                    // 悬停才给底色，平时全透明
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        // 胶囊：圆角取自身高度的一半（和顶部候选条一致）
                        radius: height / 2
                        color: cellMouse.containsMouse
                               ? Theme.withAlpha(Theme.primary, 0.18)
                               : "transparent"
                    }

                    Text {
                        id: labelText

                        anchors.centerIn: parent
                        // implicitWidth 带小数，取到它时 Text.width 是浮点，
                        // 亚像素排版会把末尾字符判成放不下。两边 ceil 再各留 1px
                        width: Math.min(Math.ceil(implicitWidth) + 1,
                                        Math.max(0, Math.ceil(cell.width - candList.unit * 2 / 3) + 2))
                        elide: Text.ElideRight
                        text: cell.modelData.t
                        color: candList.fgColor
                        font.pixelSize: candList.candFontSize
                        font.weight: Font.Normal
                    }

                    // 涟漪：trigger 后自行淡出
                    DRipple {
                        id: cellRipple
                        anchors.fill: parent
                        anchors.margins: 2
                        cornerRadius: parent.height / 2
                        rippleColor: Theme.primary
                    }

                    MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        // 用原始全局下标选词：显示顺序和 addon 下标不是一回事
                        onClicked: candList.controller.selectCandidate(cell.modelData.i)
                        onPressed: mouse => cellRipple.trigger(mouse.x, mouse.y)
                    }

                    // 分隔线：竖在容器右侧空隙正中，行末不画
                    Rectangle {
                        visible: cell.modelData.sep === true
                        x: cell.width + Math.round(candList.gap / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Math.round(candList.rowH * 0.5)
                        color: Theme.withAlpha(candList.fgColor, 0.3)
                    }
                }
            }
        }
    }

    // 空状态提示（放在列表外面：ListView 的子项会跟着 contentY 滚）
    Text {
        anchors.centerIn: candView
        visible: candList.rows.length === 0
        text: {
            if (!candList.controller)
                return ""
            return candList.controller.candLoading
                ? candList.controller.tr("Loading…")
                : candList.controller.tr("No candidates")
        }
        color: Theme.withAlpha(candList.controller ? candList.fgColor : Theme.surfaceText, 0.4)
        font.pixelSize: candList.candFontSize
    }

    // 右侧一列：上两行翻页、下两行退格/回车，中间留空（绝对坐标，不用 Column）
    readonly property real scrollStep: 0.9

    // 一屏滚动 90%：留一成重叠，用户能看出「接着上一屏」而不是跳到新地方。
    // 给调试入口读当前滚动位置
    function contentYOf() {
        return candView.contentY
    }

    function scrollBy(direction) {
        const maxY = Math.max(0, candView.contentHeight - candView.height)
        candView.contentY = Math.max(0, Math.min(maxY,
            candView.contentY + direction * candView.height * scrollStep))
    }

    // 四个按钮贴列表页的首尾：上两个占前两行、下两个占最后两行。
    // 不能用主键盘行高（keyH）来排行号——候选行高是 rowH（keyH 的 0.72），
    readonly property var sideButtons: [
        { pos: "top0", icon: "keyboard_arrow_up", act: "up" },
        { pos: "top1", icon: "keyboard_arrow_down", act: "down" },
        { pos: "bottom0", icon: "backspace", act: "backspace" },
        { pos: "bottom1", icon: "keyboard_return", act: "enter" }
    ]

    // 四个按钮的高度固定为主键盘的标准键高，不跟着候选行高浮动
    // （rowH 是按字号推的，随键盘缩放和字体变化，按钮跟着变会忽大忽小）。
    readonly property real sideKeyH: keyH
    readonly property real sideRowStep: sideKeyH + gap

    // 首尾各两个，中间整段留空
    function sideButtonY(pos) {
        switch (pos) {
        case "top0": return 0
        case "top1": return sideRowStep
        case "bottom0": return Math.max(sideRowStep * 2,
                                        candList.height - sideRowStep * 2)
        default: return Math.max(sideRowStep * 3,
                                 candList.height - sideRowStep)
        }
    }

    Repeater {
        id: sideRepeater
        model: candList.sideButtons

        delegate: Rectangle {
            id: sideBtn
            required property var modelData
            // 把点击入口暴露给 candList（模拟点击用）
            property alias pressArea: press

            readonly property bool isKey: modelData.act === "backspace"
                                          || modelData.act === "enter"

            x: parent.width - width
            y: candList.sideButtonY(modelData.pos)
            width: candList.colW
            // 固定高度（见 sideKeyH 的说明），不跟随候选行高
            height: candList.sideKeyH
            // 圆角、底色、图标色都跟主键盘的特殊键一致（Tab / Enter 那种）：
            // 这一列是键区的一部分，不该看起来像另一套控件。
            radius: Math.min(Theme.cornerRadius, candList.sideKeyH * 0.16)
            color: Theme.surfaceContainerHighest
            opacity: press.pressed ? 0.72 : 1
            Behavior on opacity {
                enabled: controller ? controller.animateCells : true
                NumberAnimation { duration: Motion.quick }
            }

            DIcon {
                anchors.centerIn: parent
                name: sideBtn.modelData.icon
                size: Math.round(candList.sideKeyH * 0.38)
                color: Theme.surfaceText
            }

            MouseArea {
                id: press
                anchors.fill: parent
                // 点击逻辑抽成函数：模拟点击和手指点走同一份
                function tapAt() {
                    switch (sideBtn.modelData.act) {
                    case "up":   candList.scrollBy(-1); break
                    case "down": candList.scrollBy(1); break
                    // 退格/回车走和主键盘完全相同的入口（keyPressed →
                    // 窗口 → daemon.handleKey），不另开一条按键通道
                    case "backspace":
                        candList.controller.keyPressed({ k: "key", l: "Backspace", c: 14 })
                        break
                    case "enter":
                        candList.controller.keyPressed({ k: "key", l: "Enter", c: 28 })
                        break
                    }
                }
                onClicked: tapAt()
            }
        }
    }

    // 模拟使用流程：点候选列表右侧的按钮（up / down / backspace / enter）
    function pointerTapSide(act) {
        for (let i = 0; i < sideRepeater.count; i++) {
            const item = sideRepeater.itemAt(i)
            if (item && item.modelData && item.modelData.act === act && item.pressArea)
                item.pressArea.tapAt()
                return true
        }
        return false
    }
}
