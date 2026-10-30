// Inline Keyboard 顶部快捷栏：左侧导航按钮、中间固定栏动作、右侧圆形动作槽。
// 编辑态显示「松手后的样子」，但 Repeater 的 model 永远指向真实数组，
// 预览只改 delegate 的**位置**、外加一个独立的幽灵块 —— model 一变就会销毁重建
// delegate，拖动手势随之断掉（见 KeyboardCard.quickBarResolved 的注释）。
import QtQuick
import qs.Common
import qs.Widgets
import "Motion.js" as Motion

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
    // 图标容器做成正圆：宽 = 高。slotW 是布局步长（间距），保持不变，
    // 靠 slotX 的居中偏移把圆放进每一格。
    readonly property real cellW: cellH

    // 第 index 个槽位的左沿
    function slotX(index) {
        return quickBar.midX + quickBar.slotGap * (index + 1) + quickBar.slotW * index
    }

    // 编辑态底色：胶囊 + surfaceContainerLow。
    // 没有动作时铺满整条（提示这里可以放），有动作时收窄到和描边同宽（成为描边内部的填充）
    Rectangle {
        readonly property bool hasItems: quickBar.slotCount > 0

        // 跟随背景透明度：用户把键盘调透后，编辑态的框不该还是一片实心
        opacity: (controller.editing ? 1 : 0) * (controller ? controller.bgOpacity : 1)
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
        }
        // 和中间的动作块一样受 animateCells 控制：打开键盘 / 切模式时
        // 布局会重排，不设 enabled 的话两端按钮会当场演一遍位移动画
        Behavior on x {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
        }
        x: quickBar.midX + (hasItems ? quickBar.frameX : 0)
        y: 0
        width: hasItems ? quickBar.frameW : quickBar.midW
        height: quickBar.height
        radius: quickBar.capRadius
        color: Theme.surfaceContainerLow
    }

    // 编辑态边框：按内部动作的范围画（第一个动作左沿 - gap 到最后一个动作右沿 + gap）
    Rectangle {
        opacity: (controller.editing && quickBar.slotCount > 0 ? 1 : 0)
                 * (controller ? controller.bgOpacity : 1)
        visible: opacity > 0.01
        Behavior on opacity {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.expand; easing.type: Easing.OutCubic }
        }
        // 和中间的动作块一样受 animateCells 控制：打开键盘 / 切模式时
        // 布局会重排，不设 enabled 的话两端按钮会当场演一遍位移动画
        Behavior on x {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
        }
        Behavior on width {
            enabled: controller ? controller.animateCells : true
            NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
        }
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
    // 插入幽灵块：拖动时显示「松手后会出现在这里」的那个动作
    GhostBlock {
        id: insertGhost
        readonly property var plan: controller.barDropPlan
        // 固定栏 → 槽的交换预览：源格将换成槽里那个动作
        readonly property var swapAction: (controller.dragOverSlot
                                           && controller.dragFrom === "bar")
            ? controller.rightSlot : null

        active: plan !== null || swapAction !== null
        action: swapAction !== null ? swapAction : controller.ghostAction
        iconRatio: 0.6
        z: 2
        y: (quickBar.height - quickBar.cellH) / 2
        width: quickBar.cellW
        height: quickBar.cellH

        // x 手动同步：绑定在 plan 为 null 时会 fallback 到第 0 格，首帧会滑过来。
        // settling 窗口吸收「出现那一帧」的绑定求值顺序问题。
        property bool allowAnim: false
        property bool settling: false
        // 交换时 barDropPlan 也会给出 insertedAt（= 被抓项腾出的那一格）
        readonly property real targetX: plan !== null
            ? quickBar.slotX(plan.insertedAt) + (quickBar.slotW - quickBar.cellW) / 2
            : x

        function syncX(animate) {
            if (!animate)
                insertGhost.allowAnim = false
            insertGhost.x = insertGhost.targetX
            if (!animate)
                Qt.callLater(function() { insertGhost.allowAnim = true })
        }

        onActiveChanged: {
            if (!active) {
                insertGhost.settling = false
                return
            }
            insertGhost.settling = true
            settleTimer.restart()
            insertGhost.syncX(false)
        }
        // 不看 active：它和 targetX 都是绑定，同一帧里可能是旧值，
        // 那样 syncX 会被跳过，幽灵块停在上一格
        onTargetXChanged: insertGhost.syncX(!insertGhost.settling)

        // 手指在固定栏里持续移动时会给足时间；这段窗口只用来吸收
        // 「刚出现那一帧」的绑定求值顺序问题
        Timer {
            id: settleTimer
            interval: 80
            onTriggered: insertGhost.settling = false
        }

        Behavior on x {
            enabled: insertGhost.allowAnim
                     && (controller ? controller.animateCells : true)
            NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
        }
    }

    Repeater {
        model: quickBar.items

        delegate: Rectangle {
            id: barCell
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
            // slotIndex = -1（预览里已被摘掉 / 会被挤出）时**保持原位**，
            // 不能钳到第 0 格：那样它先跳到最左边，落位时再从最左边滑回来，
            // 看起来就是「从第一项冒出来又滑过去」。
            property real lastValidX: 0
            readonly property real cellX: slotIndex >= 0
                ? quickBar.slotX(slotIndex) + (quickBar.slotW - quickBar.cellW) / 2
                : lastValidX
            x: cellX
            onCellXChanged: if (slotIndex >= 0) lastValidX = cellX
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
                // slotIndex < 0 = 位置还没定（预览里已被摘掉 / 会被挤出）。
                // 这时 x 停在最后有效位置（见上面的 cellX），不让它参与动画。
                enabled: slotIndex >= 0 && !leaving
                         && (controller ? controller.animateCells : true)
                NumberAnimation { duration: Motion.shift; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                // leaving 的项不等淡出：淡出会让人看着它在固定栏里慢慢消失，
                // 直接隐藏更干净。
                enabled: !leaving && (controller ? controller.animateCells : true)
                NumberAnimation { duration: Motion.fade; easing.type: Easing.OutCubic }
            }

            // 和右侧固定按钮一样的涟漪。写在 ActionIcon 之前，
            // 让涟漪铺在图标下面而不是盖住它。
            Ripple {
                id: barRipple
                anchors.fill: parent
                // 动作块是胶囊形，涟漪按高度的一半裁圆角
                cornerRadius: parent.height / 2
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
                onPressed: mouse => barRipple.press(mouse.x, mouse.y)
                onReleased: barRipple.release()
                onCanceled: barRipple.release()
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
                dragItem: barCell
            }
        }
    }

    Repeater {
        model: controller.quickBarItems

        delegate: Rectangle {
            id: slotCell
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
            // 激活态用**主色实心**（图标转 onPrimary）—— 只描边区分不够明显。
            readonly property bool slotActive: !controller.editing && isSlot
                                               && slotState === "active"
            color: (isConfirm || slotActive)
                   ? Theme.primary
                   : (controller.editing && isSlot
                      ? (slotGhost ? Theme.surfaceContainerLow : Theme.surfaceContainer)
                      : Theme.surfaceContainerHigh)
            // 动作槽在编辑态高亮描边，表示可以拖东西进来替换。
            // 非编辑态的激活态改用主色实心底，不需要描边
            border.width: controller.editing && isSlot
                          ? (controller.dragOverSlot ? 3 : 2) : 0
            border.color: Theme.primary
            scale: controller.editing && isSlot && controller.dragOverSlot ? 1.12 : 1
            Behavior on scale {
                enabled: controller ? controller.animateCells : true
                NumberAnimation { duration: Motion.micro; easing.type: Easing.OutCubic }
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
                                 : ((isConfirm || slotActive) ? Theme.onPrimary
                                    : Theme.withAlpha(controller.fg,
                                                      slotState === "disabled" ? 0.4 : 0.8))
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
                dragItem: slotCell
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
                        controller.modeChangeRequested("keys")
                        return
                    }
                    // 编辑态只有 index 0（确认）可点，槽让位给拖动手势
                    if (controller.editing) {
                        controller.editing = false
                        return
                    }
                    if (!isSlot)
                        controller.modeChangeRequested(
                            controller.mode === "functions" ? "keys" : "functions")
                    else if (controller.slotActionId !== "")
                        controller.quickAction(controller.slotActionId)
                }
            }
        }
    }
}
