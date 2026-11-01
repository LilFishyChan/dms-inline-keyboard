import "motion.js" as Motion
import "alpha.js" as Alpha
// Inline Keyboard 顶部候选条
// 布局规则（和主键盘共用同一套度量）：
import QtQuick
import qs.Common
import qs.DCommon.Common
import qs.DCommon.Widgets
import qs.Widgets

Item {
    // 候选消失时**不**自动收起：选字后 preedit 清空、候选栏会隐藏，那时收起展开页就看不到列表原地更新了。收起只由用户点 × 触发。

    id: candArea

    property var controller: null
    // 必须等于 topArea 的高度。自己算更大的值（preeditH + candH）会压到数字行。
    readonly property real areaH: parent ? parent.height : controller.candH
    // 预编辑由谁画：客户端在画就不重复显示（fcitx5 的 Composing text 模式）
    // 应用已把预编辑渲染进输入框时不重复显示
    readonly property bool hasPreedit: (controller.preedit || "") !== "" && !controller.fcitxPreeditEmbedded
    // 可见性由卡片按输入法行为算（有候选才显示）。
    // 这里**不能**再叠 preedit 条件：那会让候选栏整条消失。
    // 和主键盘一致的度量
    readonly property real unit: controller.unit || 63
    readonly property real gap: controller.gap || 6
    // 容量由卡片按列表前几项量出，这里不再自己算，避免两边得出不同结果
    // 右侧展开按钮那一列：宽度跟着按钮走（按钮直径 = quickH），后面留一个间距
    readonly property real trailW: Math.round(controller.quickH) + gap
    readonly property var pool: controller ? controller.candBarSlice : []
    readonly property int poolLen: pool.length
    readonly property int fitCount: poolLen
    // 进入动画只播一次：候选变化会让 delegate 重建，重建时不能再演一遍
    property bool entered: false
    // 首项上一次的宽度：delegate 重建后从这里起步，宽度过渡才不会丢
    property real lastFirstW: 0
    // 量文字宽度用（必须和下面 Text 的字体一致）
    // 和按键主标签同一比例（Key.qml mainLabelRatio），候选看起来才和键帽上的字一致
    readonly property int candFontSize: Math.round((controller.keyH || 64) * 0.32)

    // 模拟使用流程：点候选栏右侧的展开按钮（见 scripts/acceptance.py）
    function pointerTapExpand() {
        expandMouse.tapAt();
        return true;
    }

    width: parent.width
    height: controller.showCandBar ? areaH : 0
    onHeightChanged: {
        if (height <= 0)
            candArea.entered = false;

    }
    visible: height > 0
    // 切换时整条淡入淡出
    opacity: controller.showCandBar ? 1 : 0
    z: 20

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
                    // 每项左右的内边距：由卡片统一给（量容量和画宽度必须同源）
                    readonly property real pad: candArea.controller && candArea.controller.candItemPad !== undefined ? candArea.controller.candItemPad : Math.round(candArea.areaH * 0.8)
                    readonly property real contentW: label.implicitWidth + pad
                    readonly property real capW: isFirst ? Math.min(contentW, firstMaxW) : contentW

                    // 行尾剩余的宽度按项数平摊，和列表一样把整行铺满
                    width: capW + Math.round((candArea.controller ? candArea.controller.candBarSlack : 0) / Math.max(1, candArea.controller ? candArea.controller.candBarCount : 1))
                    height: parent.height

                    Rectangle {
                        id: capsule

                        // delegate 刚建时 parent 尺寸还是 0，减内缩会得到负数
                        readonly property real targetW: Math.max(0, parent.width)
                        // 高度取顶栏的目标行高，不跟容器出现/消失的高度动画走，否则会比圆钮矮一截
                        readonly property real targetH: Math.max(0, candArea.areaH)
                        // 瞬移开关：设起始态时把时长压到 0，避免从终值反向过渡
                        property bool snapping: false
                        // 首次出现从按钮宽度起步；重建（候选数量变了）从上一次的宽度接上
                        property real animW: !isFirst ? targetW : (candArea.entered ? (candArea.lastFirstW > 0 ? candArea.lastFirstW : targetW) : candArea.controller.quickH)
                        property real animH: targetH

                        x: 0
                        y: 0
                        width: animW
                        height: animH
                        // 胶囊形：半径取一半高度
                        radius: Theme.fullRadius(width, animH)
                        color: isFirst ? Theme.chipSurface : "transparent"
                        // 布局完成前 target* 是 0，这时候启动动画只会把起点写成 0
                        onTargetWChanged: {
                            if (capsule.snapping || capsule.targetW <= 0)
                                return ;

                            if (isFirst)
                                candArea.lastFirstW = capsule.animW;

                            if (!isFirst) {
                                capsule.animW = capsule.targetW;
                                return ;
                            }
                            if (!candArea.entered) {
                                // 首次出现：先瞬间落成按钮宽，再切 entered（切它会触发绑定重算）
                                capsule.snapping = true;
                                capsule.animW = candArea.controller.quickH;
                                capsule.animH = candArea.controller.quickH;
                                candArea.entered = true;
                                Qt.callLater(function() {
                                    capsule.snapping = false;
                                    Qt.callLater(function() {
                                        capsule.animW = capsule.targetW;
                                        capsule.animH = capsule.targetH;
                                    });
                                });
                            } else {
                                // 重建时从上一次宽度接上；必须延后一帧，初始化期间 Behavior 不拦
                                Qt.callLater(function() {
                                    capsule.animW = capsule.targetW;
                                });
                            }
                        }
                        onTargetHChanged: {
                            if (capsule.snapping || capsule.targetH <= 0)
                                return ;

                            capsule.animH = capsule.targetH;
                        }

                        // 打字时跟着滑
                        Behavior on animW {
                            enabled: controller ? controller.animationsEnabled : true
                            NumberAnimation {
                                duration: capsule.snapping ? 0 : Motion.shift
                                easing.type: Easing.OutCubic
                            }

                        }

                        Behavior on animH {
                            enabled: controller ? controller.animationsEnabled : true
                            NumberAnimation {
                                duration: capsule.snapping ? 0 : Motion.shift
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    StyledText {
                        id: label

                        // 不能用 anchors.centerIn：锚点会反过来设置 width，和下面的绑定打架，elide 就按错的值判断。
                        x: Math.round((parent.width - width) / 2)
                        y: Math.round((parent.height - height) / 2)
                        // 只在超出上限时才限制宽度，正常词按内容排。
                        // ceil 给 1px 余量：capW - pad 是浮点，和 implicitWidth
                        width: Math.min(Math.ceil(implicitWidth) + 1, Math.max(0, Math.ceil(capW - pad) + 1))
                        elide: isFirst ? Text.ElideLeft : Text.ElideRight
                        // 老版本 QML 的 JS 引擎不支持 ?? 和 ?.，用三元代替
                        text: {
                            const item = candArea.pool[index];
                            if (item === undefined || item === null)
                                return "";

                            return item.t !== undefined ? String(item.t) : String(item);
                        }
                        color: isFirst ? Theme.primary : candArea.controller.fg
                        font.pixelSize: candArea.candFontSize
                        font.weight: isFirst ? Font.DemiBold : Font.Normal
                    }

                    StateLayer {
                        id: mouse

                        // StateLayer 自带 hover/pressed 状态层和涟漪，不用自己判断 containsMouse
                        anchors.fill: parent
                        stateColor: Theme.onSurface
                        // 显式引用胶囊：StateLayer 初始化时 parent 还是 null，取 parent.radius 会拿到 undefined
                        cornerRadius: capsule.radius
                        onClicked: {
                            // 用原始全局下标选词：显示顺序和 addon 下标不是一回事
                            const item = candArea.pool[index] || {
                            };
                            candArea.controller.selectCandidate(item.i !== undefined ? item.i : index);
                        }
                    }

                    // 分隔线画在「间距正中间」：从容器右边缘往外推半个间距
                    Rectangle {
                        visible: index < candArea.fitCount - 1
                        x: parent.width + Math.round(candArea.gap / 2)
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Math.round(candArea.areaH * 0.42)
                        color: Theme.withAlpha(candArea.controller.fg, Alpha.Disabled)
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

            DActionButton {
                id: expandButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: Math.round(candArea.controller.quickH)
                // 展开态直接换图标，不走旋转（DActionButton 的 rotation 会连底色一起转）
                iconName: candArea.controller.candListOpen ? "keyboard_arrow_up" : "keyboard_arrow_down"
                tooltipText: candArea.controller ? (candArea.controller.candListOpen ? candArea.controller.tr("Collapse candidates") : candArea.controller.tr("Expand candidates")) : ""
                iconSize: Math.round(candArea.controller.quickH * 0.5)
                iconColor: candArea.controller.candListOpen ? Theme.primary : Theme.withAlpha(candArea.controller.fg, Alpha.Strong)
                backgroundColor: Theme.chipSurface
                stateColor: Theme.primary

                function tapAt() {
                    candArea.controller.toggleCandList();
                }

                onClicked: tapAt()
            }

        }

    }

    Rectangle {
        id: preeditBadge

        visible: candArea.hasPreedit
        anchors.bottom: panel.top
        anchors.bottomMargin: 5
        anchors.left: panel.left
        width: preeditLabel.width + 20
        height: preeditLabel.height + 8
        radius: Theme.cornerRadiusS
        color: Theme.withAlpha(Theme.hostSurface, controller.bgOpacity)

        StyledText {
            id: preeditLabel

            anchors.centerIn: parent
            text: controller.preedit || ""
            color: Theme.primary
            // 和候选词同一个字号基准（键高的同一比例），两处不会随顶栏高度各自漂移
            font.pixelSize: candArea.candFontSize
            font.weight: Font.Medium
        }

    }

    // 和快捷栏 / 分类栏用同一个时长，三者交叉淡入淡出才对得上
    Behavior on opacity {
        enabled: controller ? (controller.animateCells && controller.animationsEnabled) : true

        NumberAnimation {
            duration: Motion.panel
            easing.type: Easing.OutCubic
        }

    }

}
