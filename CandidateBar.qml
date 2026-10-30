// Inline Keyboard 顶部候选条
// 布局规则（和主键盘共用同一套度量）：
import QtQuick
import qs.Common
import qs.Widgets
import "Motion.js" as Motion
import qs.DCommon.Widgets

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

    // 顶栏和候选列表页是同一个列表的两段：卡片按列表前几项量出容量
    // 这里不再自己算，避免两边各量一次得出不同结果。
    readonly property real trailW: unit + gap

    readonly property var pool: controller ? controller.candBarSlice : []
    readonly property int poolLen: pool.length
    readonly property int fitCount: poolLen

    // 量文字宽度用（必须和下面 Text 的字体一致）
    // 和按键主标签同一比例（Key.qml mainLabelRatio），候选看起来才和键帽上的字一致
    readonly property int candFontSize: Math.round((controller.keyH || 64) * 0.32)

    Rectangle {
        id: panel

        anchors.fill: parent
        color: "transparent"

        Row {
            id: candRow

            anchors.left: parent.left
            anchors.right: parent.right
            // 右边界留给展开按钮那一列，宽度和 listW 同式
            anchors.rightMargin: candArea.trailW
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: candArea.gap
            clip: true

            Repeater {
                model: candArea.fitCount

                delegate: Item {
                    required property int index

                    readonly property bool isFirst: index === 0
                    // 首项最多占候选栏的三分之二，再长就省略**前面**
                    // （输入法首项通常是用户正在打的那个词，末尾更要紧）。
                    readonly property real firstMaxW: candArea.width * 2 / 3
                    readonly property real pad: candArea.unit * 2 / 3
                    readonly property real contentW: label.implicitWidth + pad
                    readonly property real capW:
                        isFirst ? Math.min(contentW, firstMaxW) : contentW

                    // 容器宽 = 文字 + 左右各 ⅓ 键宽
                    width: capW
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        // 胶囊形：半径取一半高度，首项高亮和悬浮反馈都是两端全圆
                        radius: height / 2
                        color: mouse.containsMouse
                               ? Theme.withAlpha(Theme.primary, 0.18)
                               : (isFirst ? Theme.withAlpha(Theme.primary, 0.13) : "transparent")
                    }

                    Text {
                        id: label
                        // 不能用 anchors.centerIn：锚点会反过来设置 width，
                        // 和下面的绑定打架，elide 就按错的值判断。
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - height) / 2)
                        // 只在超出上限时才限制宽度，正常词按内容排。
                        // ceil 给 1px 余量：capW - pad 是浮点，和 implicitWidth
                        width: Math.min(Math.ceil(implicitWidth) + 1,
                                        Math.max(0, Math.ceil(capW - pad) + 1))
                        elide: isFirst ? Text.ElideLeft : Text.ElideRight
// 老版本 QML 的 JS 引擎不支持 ?? 和 ?.，用三元代替
                        text: {
                            const item = candArea.pool[index]
                            if (item === undefined || item === null)
                                return ""
                            return item.t !== undefined ? String(item.t)
                                                        : String(item)
                        }
                        color: isFirst ? Theme.primary : candArea.controller.fg
                        font.pixelSize: candArea.candFontSize
                        font.weight: isFirst ? Font.DemiBold : Font.Normal
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            // 用原始全局下标选词：显示顺序和 addon 下标不是一回事
                            const item = candArea.pool[index] || {}
                            candArea.controller.selectCandidate(
                                item.i !== undefined ? item.i : index)
                        }
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

        // 常驻显示：不管候选放不放得下都给入口，点它翻到候选列表页。
        // 外层占满一列（一个标准键宽 + 间距），保证右侧留白和
        Item {
            id: expandTrail

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: candArea.trailW
            height: candArea.areaH

            Rectangle {
                id: expandButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(candArea.controller.quickH)
                height: width
                radius: width / 2
                // 和 QuickBar 右侧固定框同一个底色
                color: Theme.surfaceContainerHigh

            DRipple {
                id: expandRipple
                anchors.fill: parent
                cornerRadius: parent.height / 2
            }

            DIcon {
                anchors.centerIn: parent
                name: "keyboard_arrow_down"
                size: Math.round(candArea.controller.quickH * 0.5)
                color: Theme.withAlpha(candArea.controller.fg, 0.8)
                // 展开状态下转 180°，变成「收起」
                rotation: candArea.controller.candListOpen ? 180 : 0
                Behavior on rotation {
                    enabled: controller ? controller.animateCells : true
                    NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
                }
            }

                MouseArea {
                    id: expandMouse
                    anchors.fill: parent
                    // 点击逻辑抽成函数：模拟点击和手指点走同一份
                    function tapAt() {
                        candArea.controller.toggleCandList()
                    }
                    onClicked: tapAt()
                    onPressed: mouse => expandRipple.trigger(mouse.x, mouse.y)
                }
            }
        }
    }

    // 模拟使用流程：点候选栏右侧的展开按钮（见 scripts/acceptance.py）
    function pointerTapExpand() {
        expandMouse.tapAt()
        return true
    }

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
