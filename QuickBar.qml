// Inline Keyboard 顶部快捷栏：左侧导航按钮、中间固定栏动作、右侧圆形动作槽。
// 编辑态显示「松手后的样子」，但 Repeater 的 model 永远指向真实数组，
// 预览只改 delegate 的**位置**、外加一个独立的幽灵块 —— model 一变就会销毁重建
// delegate，拖动手势随之断掉（见 KeyboardCard.quickBarResolved 的注释）。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: quickBar

    // KeyboardCard 根：状态、函数与信号的唯一来源
    property var controller: null

    width: parent.width
    height: controller.quickH

    // 两端固定按钮是圆形，直径 = 行高
    readonly property real btnW: controller.quickH
    // 中间组：从左边固定按钮右沿到右边固定按钮左沿
    readonly property real midX: btnW + controller.gap
    readonly property real midW: Math.max(0, width - 2 * (btnW + controller.gap))

    // ⚠ 必须是稳定的真实数组：它同时是 Repeater 的 model
    readonly property var items: controller.quickBarActions || []
    // 松手后的样子，只用来算位置（多一个或少一个时让位）
    readonly property var resolved: controller.quickBarResolved || []
    readonly property int slotCount: resolved.length
    readonly property real slotW: controller.quickH * 2
    readonly property real slotGap: slotCount > 0
        ? (midW - slotCount * slotW) / (slotCount + 1) : 0
    readonly property real capRadius: height / 2

    // 动作范围（两端各多留一个键间距）→ 编辑态边框按它画，有动作才有长度
    readonly property real contentRight: slotCount > 0
        ? slotGap + (slotCount - 1) * (slotW + slotGap) + slotW : 0
    readonly property real frameX: Math.max(0, slotGap - controller.gap)
    readonly property real frameW: slotCount > 0
        ? Math.min(midW, contentRight - slotGap + 2 * controller.gap) : 0

    // 动作块比槽位小一圈：上下左右各留几像素，免得贴住编辑态的边框
    readonly property real cellH: Math.round(height * 0.84)
    readonly property real cellW: Math.round(slotW * 0.94)

    // 第 index 个槽位的左沿
    function slotX(index) {
        return quickBar.midX + quickBar.slotGap * (index + 1) + quickBar.slotW * index
    }

    // 编辑态底色：胶囊 + surfaceContainerLow。
    // 没有动作时铺满整条（提示这里可以放），有动作时收窄到和描边同宽（成为描边内部的填充）
    Rectangle {
        readonly property bool hasItems: quickBar.slotCount > 0

        opacity: controller.editing ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        x: quickBar.midX + (hasItems ? quickBar.frameX : 0)
        y: 0
        width: hasItems ? quickBar.frameW : quickBar.midW
        height: quickBar.height
        radius: quickBar.capRadius
        color: Theme.surfaceContainerLow
    }

    // 编辑态边框：按内部动作的范围画（第一个动作左沿 - gap 到最后一个动作右沿 + gap）
    Rectangle {
        opacity: controller.editing && quickBar.slotCount > 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        x: quickBar.midX + quickBar.frameX
        y: 0
        width: quickBar.frameW
        height: quickBar.height
        radius: quickBar.capRadius
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
    }

    // 真实动作块：胶囊形。拖动时按「松手后的位置」让位，被挤出的淡出
    Repeater {
        model: quickBar.items

        delegate: Rectangle {
            required property int index
            required property var modelData

            // 松手后它排第几；-1 表示会被挤出固定栏
            readonly property int slotIndex: controller.quickBarIndexFor(modelData.id)
            readonly property bool leaving: slotIndex < 0
            // 动作自身状态（避让窗口开着 / 当前是浮窗…）→ 和列表磁贴同一套
            readonly property string actState: controller.actionStates[modelData.id] || "default"
            readonly property bool isActive: actState === "active"
            // 当前不可用（比如浮动模式下「避让窗口」没意义）→ 和列表一样降透明度
            readonly property bool isDisabled: actState === "disabled"

            x: quickBar.slotX(Math.max(0, slotIndex)) + (quickBar.slotW - quickBar.cellW) / 2
            y: (quickBar.height - quickBar.cellH) / 2
            width: quickBar.cellW
            height: quickBar.cellH
            radius: quickBar.cellH / 2
            // 非编辑态普通动作不要底色（只图标）；编辑态给 surfaceContainer 方便拖；
            // 激活态和右侧动作槽统一：surfaceContainerHigh 底 + primary 图标。
            // 不用主题色实心 —— 那一排里两个"选中"用两种画法会显得像两套设计。
            color: controller.editing
                   ? Theme.surfaceContainer
                   : (isActive ? Theme.surfaceContainerHigh : "transparent")
            opacity: leaving ? 0 : (isDisabled ? 0.5 : 1)
            z: leaving ? 0 : 1
            Behavior on x {
                enabled: controller.animateCells
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            ActionIcon {
                anchors.centerIn: parent
                action: modelData
                size: Math.round(controller.quickH * 0.5)
                // 编辑态下所有动作都按默认形态显示：那是在排布动作，
                // 不是在看状态，染色只会干扰对「拖哪个」的判断。
                color: (!controller.editing && isActive)
                       ? Theme.primary
                       : Theme.withAlpha(controller.fg, 0.85)
            }

            MouseArea {
                anchors.fill: parent
                enabled: !controller.editing && !parent.leaving
                acceptedButtons: Qt.LeftButton
                onClicked: controller.quickAction(modelData.id)
            }

            // 编辑态：可以拖到别的位置 / 拖进槽 / 拖回列表。
            // ⚠ 不能加 !leaving：从固定栏往外拖时，这个块会被移出预览 → leaving 变 true，
            // 若 enabled 也跟着变 false，拖动手势会被就地取消（表现为"跟手块不动"）
            DragInitiator {
                enabled: controller.editing
                controller: quickBar.controller
                owner: "bar"
                ownerIndex: index
                payload: modelData
            }
        }
    }

    // 插入幽灵块：拖动时显示「松手后会出现在这里」的那个动作
    GhostBlock {
        readonly property var plan: controller.barDropPlan

        active: plan !== null
        action: controller.ghostAction
        iconRatio: 0.6
        z: 2
        x: quickBar.slotX(plan !== null ? plan.insertedAt : 0)
           + (quickBar.slotW - quickBar.cellW) / 2
        y: (quickBar.height - quickBar.cellH) / 2
        width: quickBar.cellW
        height: quickBar.cellH
        Behavior on x {
            enabled: controller.animateCells
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
    }

    // 两端固定按钮：index 0 导航 / 确认，index 1 圆形动作槽
    Repeater {
        model: controller.quickBarItems

        delegate: Rectangle {
            required property int index
            required property var modelData

            readonly property bool isSlot: modelData.kind === "slot"
            // 空槽在非编辑态不显示（省掉一个空圆）；
            // 透明度面板例外 —— 那个位置的圆钮是「取消」
            visible: !isSlot || controller.editing
                     || controller.mode === "transparency"
                     || controller.slotActionId !== ""

            // 松手后槽里会是什么：拖到槽上 = 被拖的动作；从槽拖出 = 空；其它 = 当前
            readonly property var slotShow: {
                if (!isSlot)
                    return null
                if (controller.dragOverSlot)
                    return controller.ghostAction
                if (controller.dragActive && controller.dragFrom === "slot")
                    return null
                return controller.rightSlot
            }
            // 幽灵预览态：将要进槽、或将从槽出去 —— 和列表/固定栏一样，先显示结果
            readonly property bool slotGhost: isSlot && controller.dragActive
                                              && (controller.dragOverSlot
                                                  || controller.dragFrom === "slot")
            // 右侧槽用 rightSlot 的内容（可被拖动替换）
            readonly property var slotData: isSlot
                ? controller.rightSlot : ({icon: "", action: ""})
            // 槽里动作的状态提到外层：底色和图标颜色都要用，之前只在
            // ActionIcon 内部算了一份
            readonly property string slotState: isSlot && slotData
                ? (controller.actionStates[slotData.id] || "default") : "default"

            // 第一个按钮在"确认"场景（编辑态 / 透明度面板）都是主题色底 + 白色对钩
            readonly property bool isConfirm: index === 0
                && (controller.editing || controller.mode === "transparency")
            // 非编辑态：键盘页显示四格（打开功能页），功能页显示 X（关闭功能页）
            readonly property string btnIcon: {
                if (isConfirm) return "check"
                if (index === 0) {
                    if (controller.mode === "keys") return "apps"
                    if (controller.mode === "transparency") return "check"
                    return "close"
                }
                // 透明度面板里右上角变成"取消"
                if (controller.mode === "transparency") return "close"
                // 右上角是圆形动作槽：有动作显示图标，空着显示加号
                return controller.slotActionId ? (slotData ? slotData.icon : "add") : "add"
            }

            // 固定的两个图标钉在两端，不参与中间的分组分布
            x: index === 0 ? 0 : (quickBar.width - quickBar.btnW)
            y: (quickBar.height - quickBar.btnW) / 2
            width: quickBar.btnW
            height: quickBar.btnW
            radius: width / 2
            // 固定按钮常驻一点底色，编辑态换成拖动提示底色。
            // 激活态就是默认底色（surfaceContainerHigh）+ primary 图标，
            // 和顶部动作栏一致；只有「确认」按钮是主题色实心。
            color: isConfirm
                   ? Theme.primary
                   : (controller.editing && isSlot
                      ? (slotGhost ? Theme.surfaceContainerLow : Theme.surfaceContainer)
                      : Theme.surfaceContainerHigh)
            // 动作槽在编辑态高亮描边，表示可以拖东西进来替换
            border.width: controller.editing && isSlot
                          ? (controller.dragOverSlot ? 3 : 2) : 0
            border.color: Theme.primary
            scale: controller.editing && isSlot && controller.dragOverSlot ? 1.12 : 1
            Behavior on scale {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            Ripple {
                id: qbRipple
                anchors.fill: parent
                // 快捷条的按钮是圆形，涟漪也要按圆形裁
                cornerRadius: parent.height / 2
            }

            // 导航按钮（index 0）用字体图标；槽（index 1）用统一的 ActionIcon
            DankIcon {
                anchors.centerIn: parent
                visible: index === 0
                name: btnIcon
                size: Math.round(controller.quickH * 0.5)
                color: isConfirm ? Theme.surface : Theme.withAlpha(controller.fg, 0.8)
            }

            // 槽里的动作：内容永远取「松手后的样子」（进槽 / 被拖走 / 不变）
            ActionIcon {
                anchors.centerIn: parent
                // 透明度面板下这个位置固定是「取消」，不显示槽里的动作
                visible: isSlot && controller.mode !== "transparency" && slotShow !== null
                action: slotShow
                size: Math.round(controller.quickH * 0.5)
                readonly property string slotState: parent.slotState
                // 编辑态下统一显示默认形态（见顶部动作块的同款说明）
                color: slotGhost ? Theme.primary
                                 : (isConfirm ? Theme.surface
                                              : ((!controller.editing && slotState === "active")
                                                 ? Theme.primary
                                                 : Theme.withAlpha(controller.fg,
                                                                   slotState === "disabled" ? 0.4 : 0.8)))
            }

            // 空槽 / 透明度面板的占位图标（编辑态被拖走时也走这里，预览"变空"）。
            // ⚠ 不能走 btnIcon：它读的是 slotActionId，从槽往外拖的那一刻那还是旧动作，
            // 会残留原来的图标（「浮动」的自绘 SVG 看着就像个手机）
            DankIcon {
                anchors.centerIn: parent
                visible: isSlot && (controller.mode === "transparency" || slotShow === null)
                name: controller.mode === "transparency" ? "close" : "add"
                size: Math.round(controller.quickH * 0.5)
                color: slotGhost ? Theme.primary
                                 : (isConfirm ? Theme.surface
                                              : Theme.withAlpha(controller.fg, 0.8))
            }

            // 编辑态：可以把槽里的动作拖回固定栏 / 列表
            DragInitiator {
                enabled: controller.editing && isSlot
                controller: quickBar.controller
                owner: "slot"
                ownerIndex: index
                payload: controller.rightSlot
            }

            MouseArea {
                anchors.fill: parent
                // index 0 是对钩/导航，编辑态也要能点；槽在编辑态让位给拖动
                enabled: !isSlot || !controller.editing
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => qbRipple.press(mouse.x, mouse.y)
                onReleased: qbRipple.release()
                onCanceled: qbRipple.release()
                onClicked: {
                    if (controller.mode === "transparency") {
                        // index 0 = 确定：保留当前透明度，回键盘页
                        // 槽 = 取消：恢复到进来之前的透明度
                        if (isSlot) {
                            controller.bgOpacity = controller.prevBgOpacity
                            controller.keyOpacity = controller.prevKeyOpacity
                        }
                        controller.mode = "keys"
                        return
                    }
                    // 编辑态只有 index 0（确认）可点，槽让位给拖动手势
                    if (controller.editing) {
                        controller.editing = false
                        return
                    }
                    if (!isSlot)
                        controller.mode = (controller.mode === "functions" ? "keys" : "functions")
                    else if (controller.slotActionId !== "")
                        controller.quickAction(controller.slotActionId)
                }
            }
        }
    }
}
