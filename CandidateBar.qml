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
    // 应用已把预编辑渲染进输入框时不重复显示
    readonly property bool hasPreedit:
        (controller.preedit || "") !== "" && !controller.fcitxPreeditEmbedded

    // 可见性由卡片按输入法行为算（有候选才显示）。
    // 这里**不能**再叠 preedit 条件：那会让候选栏整条消失。
    readonly property bool imHasCandidates: controller.showCandBar

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

    // 顶部只取 items（addon 给的前 18 个，都是单字），宽度可算。
    readonly property var pool: {
        const arr = controller.candidates || []
        return arr.length > kPool ? arr.slice(0, kPool) : arr
    }

    // 池子长度单独用一个 int 表示：pool 是 property var 存的数组，
    // 内部元素变了不会通知绑定（QML 的经典坑）。int 是值类型，可靠。
    readonly property int poolLen:
        Math.min((controller.candidates || []).length, kPool)

    // 量文字宽度用（必须和下面 Text 的字体一致）
    readonly property int candFontSize: Math.round((controller.keyH || 64) * 0.42)

    TextMetrics {
        id: measure
        font.pixelSize: candArea.candFontSize
        font.weight: Font.Normal
    }

    // 能放下的候选个数：累加「文字宽 + 左右内边距 + 间距」，下一个放不下就停。
    // 放不下的直接不画（没有展开列表了，超出部分由 clip 裁掉）。
    readonly property real availWidth: {
        return width - 10 - 6
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

    // ---------- 候选面板 ----------
    Rectangle {
        id: panel

        anchors.fill: parent
        color: "transparent"

        Row {
            id: candRow

            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
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
                        font.pixelSize: candArea.candFontSize
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

    // 候选消失时**不**自动收起：选字后 preedit 清空、候选栏会隐藏，
    // 那时收起展开页就看不到列表原地更新了。收起只由用户点 × 触发。
}
