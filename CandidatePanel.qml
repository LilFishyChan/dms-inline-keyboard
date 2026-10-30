// 候选词列表页：覆盖主键盘的按键区，把候选摊开。
//
// 布局（尺寸都从键区推出来，不写死）：
//   左侧 Flickable 宽 = 键区宽 - 一列（unit + gap），高 = 键区高
//     内部按候选栏同一套排法：每个词包一层容器，左右各留 ⅓ 标准键宽，
//     词之间一个 gap，排满一行自动换行。
//   右侧一列宽 = unit：顶上两行 + 底下两行各一个空白键帽，中间一行留空
//
// 虚拟化（关键）：
//   不拿 Flow + Repeater 铺全部候选 —— 实测 1000 词那样做展开瞬间要吃
//   700MB，反复开关还冲上过 6GB 把 qs 搞崩，因为 Repeater 会给每一项都
//   实例化一套图形对象，而 Flow 没法懒加载。
//   现在分两步：
//     1. rebuildLayout() 用 TextMetrics 一次性算出每项的 x/y/宽（纯算术，
//        1000 项也就一两毫秒），结果缓存进 rows
//     2. 只把「可视行 ±1」这一段交给 Repeater 实例化
//   于是对象数跟候选总数无关，恒定几十个；滚动时只是换一段 model。

import QtQuick
import qs.Common
import qs.Widgets
import "Motion.js" as Motion

Item {
    id: candList

    property var controller: null

    // 度量全部来自卡片（controller 就是 KeyboardCard）
    readonly property real unit: controller.unit || 63
    readonly property real keyH: controller.keyH || 64
    readonly property real gap: controller.gap || 6
    readonly property int rowCount: controller.keyRowCount || 5

    // 字号和顶部候选栏一致（那边也是 keyH * 0.42）
    readonly property int candFontSize: Math.round(keyH * 0.42)
    readonly property real rowH: Math.max(keyH * 0.72, candFontSize * 1.5)

    readonly property real colW: unit
    readonly property real listW: Math.max(0, width - colW - gap)
    readonly property real areaH: rowCount * keyH + Math.max(0, rowCount - 1) * gap

    // 收起时由 KeyboardCard 置 0，让布局清空、不再持有渲染对象
    property int shownCountOverride: -1
    readonly property bool active: shownCountOverride !== 0

    // controller 在构造期可能还是 null，所有取它的地方都要有兜底，
    // 否则组件直接报 TypeError、整个插件 disabled（实测）。
    readonly property color fgColor: controller ? controller.fg : Theme.surfaceText

    width: parent ? parent.width : 0
    height: areaH

    // ---------------------------------------------------------------
    // 布局缓存：每个元素 { x, y, w, t, i, sep }
    //   sep = 这一项右边要不要画分隔线（行内非末项才画）
    // ---------------------------------------------------------------
    property var items: []
    property real contentH: 0
    property int layoutSeq: 0

    TextMetrics {
        id: measure
        font.pixelSize: candList.candFontSize
        font.weight: Font.Normal
    }

    function rebuildLayout() {
        if (!active || !controller) {
            items = []
            contentH = 0
            layoutSeq++
            return
        }
        const src = controller.candListSlice || []
        const availW = listW
        const pad = unit * 2 / 3
        const step = rowH + gap
        const out = []

        let rowY = 0
        let x = 0
        let rowStart = 0

        for (let n = 0; n < src.length; n++) {
            const item = src[n] || {}
            const text = item.t !== undefined ? String(item.t) : String(item)
            measure.text = text
            // 容器宽 = 文字 + 左右各 ⅓ 键宽；上限是整行宽度，
            // 再长就独占一行，文字由 delegate 用省略号截断
            // ceil 掉小数：小数宽度交给渲染层会各自舍入，
            // 累加几格之后右边界就和 availW 对不上
            const w = Math.min(Math.ceil(measure.advanceWidth + pad), availW)

            if (x > 0 && x + w > availW) {
                // 换行：把上一行最后一项的 sep 关掉
                if (out.length > rowStart)
                    out[out.length - 1].sep = false
                rowY += step
                x = 0
                rowStart = out.length
            }

            out.push({ x: x, y: rowY, w: w, t: text, sep: true,
                       i: item.i !== undefined ? item.i : n })
            x += w + gap
        }
        // 整个列表最后一项也不画分隔线
        if (out.length > 0)
            out[out.length - 1].sep = false

        items = out
        contentH = Math.max(0, rowY + step)
        layoutSeq++
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
    // 重排节流（throttle），不是 debounce。
    //
    // debounce 的语义是「停下 80ms 才动」，连续打字时永远轮不到触发，
    // 列表就看起来一直不更新。这里要的是「每 80ms 最多重排一次，
    // 但打字过程中一直在更新」，所以用 throttle + 尾部补一次。
    //
    // 80ms：最快那批打字者的键间隔约 120ms，窗口要明显小于它才不会整段丢更新；
    // 再小会频繁重排，再大就开始吞快速输入。
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
            // 节流窗口，那就是用户感知到的「选完词列表慢半拍」。
            if (candList.controller && candList.controller.recentSelect)
                candList.forceRelayout()
            else
                candList.requestRelayout()
        }
    }

    // ---------------------------------------------------------------
    // 左侧：滚动区，只实例化可视行
    // ---------------------------------------------------------------
    Flickable {
        id: flick

        anchors.left: parent.left
        anchors.top: parent.top
        width: candList.listW
        height: candList.areaH
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: 2400
        contentWidth: width
        contentHeight: Math.max(height, candList.contentH)

        readonly property int step: candList.rowH + candList.gap

        // 可视范围内要实例化的项。first/last 用二分找也行，但行数上千时
        // 线性扫也不贵；滚动时 contentY 变化频率高，所以用位运算近似，
        // 上下各多给一行避免露白。
        readonly property var visibleItems: {
            const seq = candList.layoutSeq
            const list = candList.items
            if (seq < 0 || list.length === 0)
                return []
            const top = Math.max(0, flick.contentY - candList.rowH)
            const bottom = flick.contentY + flick.height + candList.rowH
            const out = []
            for (let n = 0; n < list.length; n++) {
                const it = list[n]
                if (it.y + candList.rowH < top)
                    continue
                if (it.y > bottom)
                    break
                out.push(it)
            }
            return out
        }

        Repeater {
            model: flick.visibleItems

            delegate: Item {
                id: cell

                required property var modelData
                required property int index

                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: candList.rowH

                // 悬停才给底色，平时全透明
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 7
                    color: cellMouse.containsMouse
                           ? Theme.withAlpha(Theme.primary, 0.18)
                           : "transparent"
                }

                Text {
                    id: labelText

                    anchors.centerIn: parent
                    // cell.width = 文字宽 + pad，减掉 pad 就正好等于文字宽，
                    // 一点余量都没有；implicitWidth 因抗锯齿常比 advanceWidth
                    // 大零点几像素，Math.min 取到那个值就会把整词省略成「砰...」。
                    // 加 1px 余量（和 CandidateBar 首项同一处理），ceil 掉小数。
                    width: Math.min(implicitWidth,
                                    Math.max(0, Math.ceil(cell.width - candList.unit * 2 / 3) + 1))
                    elide: Text.ElideRight
                    text: cell.modelData.t
                    color: candList.fgColor
                    font.pixelSize: candList.candFontSize
                    font.weight: Font.Normal
                }

                // 涟漪：用现有 MouseArea 的按下/松开驱动，不改事件模型
                Ripple {
                    id: cellRipple
                    anchors.fill: parent
                    anchors.margins: 2
                    cornerRadius: 7
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // 用原始全局下标选词：显示顺序和 addon 下标不是一回事
                    onClicked: candList.controller.selectCandidate(cell.modelData.i)
                    onPressed: mouse => cellRipple.press(mouse.x, mouse.y)
                    onReleased: cellRipple.release()
                    onCanceled: cellRipple.release()
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

        // 空状态提示
        Text {
            anchors.centerIn: parent
            visible: candList.items.length === 0
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
    }

    // ---------------------------------------------------------------
    // 右侧一列：上面两个翻页、下面两个退格/回车，中间留空
    //
    // 用绝对坐标而不是 Column：Column 里插空 Item 占位时，间距和高度
    // 容易算错，实测中间那行会多冒一个色块。
    // ---------------------------------------------------------------
    readonly property real scrollStep: 0.9

    // 一屏滚动 90%：留一成重叠，用户能看出「接着上一屏」而不是跳到新地方。
    // 给调试入口读当前滚动位置
    function contentYOf() {
        return flick.contentY
    }

    function scrollBy(direction) {
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        flick.contentY = Math.max(0, Math.min(maxY,
            flick.contentY + direction * flick.height * scrollStep))
    }

    // 四个按钮贴列表页的首尾：上两个占前两行、下两个占最后两行。
    //
    // 不能用主键盘行高（keyH）来排行号——候选行高是 rowH（keyH 的 0.72），
    // 两者混用会让按钮和左侧候选行整体错位，越往下偏得越多。
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
        model: candList.sideButtons

        delegate: Rectangle {
            id: sideBtn
            required property var modelData

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

            DankIcon {
                anchors.centerIn: parent
                name: sideBtn.modelData.icon
                size: Math.round(candList.sideKeyH * 0.38)
                color: Theme.surfaceText
            }

            MouseArea {
                id: press
                anchors.fill: parent
                onClicked: {
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
            }
        }
    }
}
