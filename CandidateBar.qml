// Inline Keyboard 顶部候选条
//
// 布局规则（和主键盘共用同一套度量）：
//   · 每个候选词包一层容器，容器左右内边距各 = ⅓ 标准键宽（unit/3）
//   · 容器之间留一个标准键间距（gap）
//   · 分隔竖线画在间距正中间
//   · 候选从前往后排，加下一个会溢出可用宽度时就停（不换行、不滚动）
//
// 数据取前 3 屏（addon 的顶部候选池），实际显示多少由可用宽度决定。
//
// 原文（拼音串）单独做成浮动小标签，浮在候选区上方、不占高度。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: candArea

    property var controller: null

    // 必须等于 topArea 的高度。自己算更大的值（preeditH + candH）会压到数字行。
    readonly property real areaH: parent ? parent.height : controller.candH
    // 预编辑由谁画：客户端在画就不重复显示（fcitx5 的 Composing text 模式）
    readonly property bool hasPreedit: (controller.preedit || "") !== ""
        && !controller.fcitxPreeditEmbedded

    // 和主键盘一致的度量
    readonly property real unit: controller.unit || 63
    readonly property real gap: controller.gap || 6

    width: parent.width
    height: controller.showCandBar ? areaH : 0
    visible: height > 0
    z: 20

    // ---------- 候选池：只取前面一小段 ----------
    // 候选栏只监控前 kPool 个，不追全量。
    // 全量动辄上千个（长拼音串 rime 能生成 4000+），为了候选栏那一行去
    // 拉全量纯属浪费：序列化 + 推送几十 KB，打字就卡了。
    // 排不下的一律进展开列表，那里才需要全量。
    readonly property int kPool: 18

    readonly property var pool: {
        const arr = controller.candidates || []
        return arr.length > kPool ? arr.slice(0, kPool) : arr
    }

    // 池子长度单独用一个 int 表示。
    // hasOverflow 不能直接写 pool.length —— pool 是 property var 存的数组，
    // 它内部元素变了不会通知绑定（QML 的经典坑，实测这里就卡住了）。
    // int 是值类型，candidates 一变就重新求值。
    readonly property int poolLen:
        Math.min((controller.candidates || []).length, kPool)

    // 量文字宽度用（和下面 Text 的字体必须一致）
    TextMetrics {
        id: measure
        font.pixelSize: Math.round(candArea.areaH * 0.44)
        font.weight: Font.Normal
    }

    // 能放下的候选个数：累加「文字宽 + 左右内边距 + 间距」，下一个放不下就停。
    //
    // 可用宽度**固定**按「展开按钮占位」来算，不随按钮显隐变化：
    // 否则按钮显隐改变宽度 → 改变 fitCount → 又改变按钮显隐，来回抖。
    // 代价是全部放下时右边会空出按钮那块，可以接受。
    readonly property real availWidth: {
        const btn = Math.round(areaH * 0.58)   // expandButton 的直径
        return width - 10 - btn - 8 - 6        // 左右边距 + 按钮 + 按钮右距
    }

    readonly property int fitCount: {
        const avail = availWidth
        if (avail <= 0 || pool.length === 0)
            return 0
        let used = 0
        let n = 0
        for (let i = 0; i < pool.length; i++) {
            measure.text = String(pool[i])
            const w = measure.advanceWidth + unit * 2 / 3 + gap
            if (used + w > avail)
                break
            used += w
            n++
        }
        return n
    }

    // 两个条件任一成立就要展开按钮：
    //   ① 池子本身排不下；
    //   ② 输入法还有更多候选（addon 的 hasMore）——候选栏只监控前面一小段，
    //      6 个全放下不代表没有第 7 个。
    // 都直接读值类型 / 底层属性：中间的派生 property bool 实测不传值。
    readonly property bool hasOverflow:
        fitCount < poolLen || controller.fcitxHasMore === true

    // ---------- 候选面板 ----------
    Rectangle {
        id: panel

        anchors.fill: parent
        color: "transparent"

        Row {
            id: candRow

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: candArea.hasOverflow ? expandButton.left : parent.right
            anchors.rightMargin: 6
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: candArea.gap
            clip: true

            Repeater {
                model: candArea.fitCount

                delegate: Item {
                    required property int index

                    // 容器宽 = 文字 + 左右各 ⅓ 键宽
                    width: label.implicitWidth + candArea.unit * 2 / 3
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 7
                        color: mouse.containsMouse
                               ? Theme.withAlpha(Theme.primary, 0.18)
                               : (index === 0 ? Theme.withAlpha(Theme.primary, 0.13) : "transparent")
                    }

                    Text {
                        id: label
                        anchors.centerIn: parent
                        text: String(candArea.pool[index] ?? "")
                        color: index === 0 ? Theme.primary : candArea.controller.fg
                        font.pixelSize: Math.round(candArea.areaH * 0.44)
                        font.weight: index === 0 ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: candArea.controller.selectCandidate(index)
                    }

                    // 分隔线画在「间距正中间」：从容器右边缘往外推半个间距
                    Rectangle {
                        visible: index < candArea.fitCount - 1
                        x: parent.width + Math.round(candArea.gap / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Math.round(candArea.areaH * 0.42)
                        color: Theme.withAlpha(candArea.controller.fg, 0.3)
                    }
                }
            }
        }

        // ---------- 展开按钮（最右）----------
        Rectangle {
            id: expandButton

            // 候选全部放得下就没有「更多」，不显示
            visible: candArea.hasOverflow
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(candArea.areaH * 0.58)
            height: width
            radius: width / 2
            color: expandMouse.containsMouse
                   ? Theme.withAlpha(Theme.primary, 0.18)
                   : Theme.withAlpha(candArea.controller.fg, 0.07)

            Text {
                anchors.centerIn: parent
                text: candArea.controller.candExpanded ? "⌃" : "⌄"
                color: candArea.controller.fg
                font.pixelSize: Math.round(expandButton.height * 0.62)
            }

            MouseArea {
                id: expandMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: candArea.controller.candExpanded = !candArea.controller.candExpanded
            }
        }
    }

    // ---------- 原文（在候选区上方，溢出卡片顶边）----------
    Rectangle {
        id: preeditBadge

        visible: candArea.hasPreedit
        anchors.bottom: panel.top
        anchors.bottomMargin: 5
        anchors.left: panel.left
        width: preeditLabel.width + 20
        height: preeditLabel.height + 8
        radius: 8
        color: Theme.withAlpha(Theme.surface, controller.bgOpacity)

        Text {
            id: preeditLabel
            anchors.centerIn: parent
            text: controller.preedit || ""
            color: Theme.primary
            font.pixelSize: Math.round(candArea.areaH * 0.4)
            font.weight: Font.Medium
        }
    }

    // 候选消失时自动收起
    onVisibleChanged: if (!visible && controller) controller.candExpanded = false
}
