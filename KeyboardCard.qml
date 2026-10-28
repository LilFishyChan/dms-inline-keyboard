// Inline Keyboard 的键盘卡片本体：顶部快捷栏 + 右上角动作槽、按键区（page1/page2）、
// 功能动作列表（含编辑态与拖放排序）、透明度面板。
// 由 KeyboardWindow（停靠）和 FloatingKeyboardWindow（浮动）共同实例化。
//
// 三个页面由 mode 切换：keys / functions / transparency。
// 拖放状态集中在根部（dragIndex / dragTarget / dragGhost / dragOwner），
// delegate 只负责把指针事件翻译成这些状态，重排逻辑在 actions.js。

import QtQuick
import "data.js" as Data
import Quickshell.Io
import qs.Common
import qs.Widgets
import "layouts/phone.js" as Layout
import "actions.js" as Actions
import "modifiers.js" as Modifiers

// 键盘主体：顶部快捷条 + 候选/快捷栏 + 键区（或功能列表） + 底部把手条
Rectangle {
    id: root

    // 尺寸（由窗口按屏幕宽度/用户设置算好后传进来）
    property real unit: 63
    property real keyH: 64
    property real gap: 6
    property real pad: 8
    property real candH: 44
    property real handleH: 30
    property bool showHandle: true
    property bool dragEnabled: false
    // 候选/快捷栏：接入 fcitx5 之前先不显示
    // 候选栏整行的开关：有候选才占位显示
    property bool showCandBar: root.fcitxCandidates.length > 0
        && !root.fcitxImKeyboard

    // 状态
    property bool fnActive: false
    // Esc 与 ` 对调（设置项）
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定）
    property var modifierStates: ({})
    property string page: "page1"
    // 点候选上屏：把索引写进 $XDG_RUNTIME_DIR/inline-keyboard-select，
    // fcitx5 的 inline-keyboard-status addon 轮询到后直接调 CandidateWord::select()——
    // 这是 fcitx5 内部的真正选词入口，等价于用户按了选择键。
    // 选词逻辑在 daemon（UI 只负责报告"点了第几个"）
    function selectCandidate(index) {
        root.selectCandidateRequested(index)
    }

    // 有候选才显示候选行；没有候选时退回快捷键行
    property bool showCandidates: root.fcitxCandidates.length > 0
    // keys = 正常键盘；functions = 快捷功能列表
    property string mode: "keys"
    // 动作列表的编辑态（拖动排序）
    property bool editing: false
    // 停靠模式下是否避让键盘：对应动作的"激活"状态
    property bool avoidWindows: true
    // 当前是否浮动窗口（浮窗下"避让窗口"没有意义 → 禁用态）
    property bool isFloating: false
    // 透明度：由插件设置决定（0.1 ~ 1.0），不跟 DMS 主题走
    property real bgOpacity: 1.0
    property real keyOpacity: 1.0
    // 进入调整面板前的值，"取消"时恢复
    property real prevBgOpacity: 1.0
    property real prevKeyOpacity: 1.0

    // 右上角圆形动作槽的内容（可被列表里的动作拖进来替换）
    property string slotActionId: "float"
    property var quickBarActions: []
    signal quickBarChanged(var list)
    // 槽里的动作从列表里按 id 找，找不到就用默认的语音输入
    readonly property var rightSlot: {
        if (!slotActionId)
            return null
        const list = actionList || []
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === slotActionId)
                return list[i]
        }
        // id 指向的动作不在表里了，也算空
        return null
    }
    property bool dragOverSlot: false
    // 固定栏落点：-1 = 没落在固定栏上；>= 0 = 插入位置（0..固定栏动作数）
    property int dragBarIndex: -1
    readonly property bool dragOverBar: root.dragBarIndex >= 0
    // 拖动来源："" 列表 / "bar" 快捷栏 / "slot" 右上角槽
    property string dragFrom: ""
    property int dragFromIndex: -1
    // 跟手的拖动块（圆形+图标），坐标是场景坐标
    property real ghostX: 0
    property real ghostY: 0
    property var ghostAction: null
    // 拖动是否进行中（DragHandler.active 的镜像，用来兜底清理）
    property bool dragActive: false
    // 拖动锁：多点触控时只认第一个开始拖的，避免新触点把状态覆盖
    property string dragOwner: ""
    // 松手瞬间关掉让位动画，直接落到目标位置
    property bool animateCells: true
    // 松手后幽灵块淡出，动画结束再真正移除
    property bool ghostFading: false
    // 按下点在"卡片"坐标系里的位置（按下时算一次，之后只加位移）
    property real pressCardX: 0
    property real pressCardY: 0
    property int dragIndex: -1
    property int dragTarget: -1

    // ── 拖动公共入口 ────────────────────────────────────────────────
    // 三种拖动源（快捷栏 bar / 右上角槽 slot / 列表格子 cell）共用这套状态机，
    // 避免每个 delegate 各写一份几乎相同的 onActiveChanged。
    // 返回 true 表示抢到拖动权；已有其他拖动进行中时返回 false 并被忽略。

    function beginDrag(source, index, centroidPos, item, action) {
        if (root.dragOwner !== "")
            return false
        root.dragOwner = source + ":" + index
        root.dragActive = true
        root.dragFrom = source === "cell" ? "" : source
        root.dragFromIndex = source === "cell" ? -1 : index
        root.dragIndex = source === "cell" ? index : -1
        root.dragTarget = source === "cell" ? index : -1
        root.ghostAction = action
        // 记下真实按下点；拖动时用「按下点 + 累计位移」，不能再叠加 centroid（会漂移）
        const origin = item.mapToItem(root, centroidPos.x, centroidPos.y)
        root.pressCardX = origin.x
        root.pressCardY = origin.y
        root.ghostX = origin.x
        root.ghostY = origin.y
        if (root.actionListRef)
            root.actionListRef.interactive = false
        return true
    }

    function updateDrag(translation) {
        root.ghostX = root.pressCardX + translation.x
        root.ghostY = root.pressCardY + translation.y
        root.updateTargetFromGhost()
        root.updateDropTargets()
    }

    // 松开：取快照 → 清状态 → 按落点分发。
    // 顺序不能反：落点写入会触发 Repeater 重建、销毁当前 delegate，
    // 之后再去读 index / parent 就是 undefined（踩过）。
    function endDrag() {
        const owner = root.dragOwner
        if (!owner) {
            // 手势已经断了（delegate 被重建、或 endDrag 被重复调用）：
            // 至少把状态清干净，别把幽灵块和 dragActive 留在界面上
            root.clearDragState()
            return
        }
        const drop = {
            source: owner.split(":")[0],
            action: root.ghostAction,
            barTarget: root.dragBarIndex,
            overSlot: root.dragOverSlot,
            inList: root.ghostInList(),
            fromIndex: root.dragIndex,
            toIndex: root.dragTarget,
            sourceIndex: root.dragFromIndex
        }
        root.clearDragState()
        if (drop.action)
            root.commitDrop(drop)
    }

    // 清空拖动相关的全部状态（快照取完之后才有意义）
    function clearDragState() {
        root.dragBarIndex = -1
        root.dragOverSlot = false
        root.dragIndex = -1
        root.dragTarget = -1
        root.dragOwner = ""
        root.dragFrom = ""
        root.dragFromIndex = -1
        root.dragActive = false
        if (root.actionListRef)
            root.actionListRef.interactive = true
        root.scheduleDragFinish()
    }

    // 按落点分发：固定栏 → 槽 → 拖回列表 → 列表内排序
    function commitDrop(drop) {
        if (drop.barTarget >= 0) {
            root.applyQuickBarDrop(drop.action, drop.barTarget, drop.source, drop.sourceIndex)
            return
        }
        if (drop.overSlot) {
            root.removeFromQuickBar(drop.sourceIndex)
            root.slotChanged(drop.action.id)
            return
        }
        if (drop.source === "bar") {
            if (drop.inList)
                root.removeFromQuickBar(drop.sourceIndex)
            return
        }
        if (drop.source === "slot") {
            if (drop.inList)
                root.returnSlotActionToList(drop.action)
            return
        }
        if (drop.inList && drop.fromIndex >= 0 && drop.toIndex >= 0
                && drop.fromIndex !== drop.toIndex) {
            // 落位立即生效（frozenList 已把新顺序摆好），不需要再演一遍位移动画
            root.animateCells = false
            root.moveAction(drop.fromIndex, drop.toIndex)
        }
    }

    // 落到固定栏：与拖动预览共用同一份 plan，保证「看到什么就得到什么」
    function applyQuickBarDrop(action, index, source, sourceIndex) {
        const plan = Actions.planQuickBarDrop(
            root.quickBarDropArgs(action, index, source, sourceIndex))
        root.freezeBarTo(plan.bar)
        root.quickBarChanged(plan.bar)
        if (plan.slotActionId !== root.slotActionId)
            root.slotChanged(plan.slotActionId)
        root.orderChanged(plan.actionList)
    }

    // 松手后先把固定栏的最终顺序冻结住，等真实数据追上来再解除 ——
    // 否则位置会先弹回拖动前的样子、数据回来后再动一次（看着像演了两遍）
    function freezeBarTo(bar) {
        root.frozenBar = bar
        freezeTimer.restart()
    }

    // 从固定栏移除某一项（拖到槽 / 拖出到列表），顺带冻结结果
    function removeFromQuickBar(index) {
        // 用 toArray：quickBarActions 可能是 QML 包过的类数组，直接 slice 会失效
        const bar = Actions.toArray(root.quickBarActions).slice()
        if (index < 0 || index >= bar.length)
            return
        bar.splice(index, 1)
        root.freezeBarTo(bar)
        root.quickBarChanged(bar)
    }

    // 按显示位置移动动作；真正的重排逻辑在 actions.js（有单测）
    function moveAction(fromDisplay, toDisplay) {
        const shown = root.availableActions || []
        const fromAction = shown[fromDisplay]
        if (!fromAction)
            return
        // 拖到最后一项之后：追加到末尾（落点索引可以等于数组长度）
        if (toDisplay >= shown.length) {
            const moved = Actions.moveActionToEndById(root.actionList, fromAction.id)
            root.frozenList = moved
            freezeTimer.restart()
            root.orderChanged(moved)
            return
        }
        const toAction = shown[toDisplay]
        if (!toAction)
            return
        const moved = Actions.moveActionById(root.actionList, fromAction.id, toAction.id)
        // 冻结：松手后到数据回来之前，列表就按「移动后」的顺序摆，别先弹回去再动画一遍
        root.frozenList = moved
        freezeTimer.restart()
        root.orderChanged(moved)
    }

    // 拖动收尾（延后一帧执行，避免和 Repeater 重建撞车）
    // delegate 里拿不到根部 Timer 的 id，统一从这里转
    function scheduleDragFinish() {
        dragDeferTimer.restart()
    }

    function reenableAnim() {
        root.animateCells = true
    }

    // 判断逻辑在 data.js（有单测），这里只负责把当前动作表传进去
    function actionExists(id) {
        return Data.actionExists(root.actionList, id)
    }


    // ── 落点动作（由 endDrag 分发）────────────────────────────────



    // 右上角槽 → 回到列表；槽留空
    function returnSlotActionToList(action) {
        root.slotChanged("")
        if (!root.actionExists(action.id))
            root.orderChanged((root.actionList || []).concat([action]))
    }


    // 根据跟手块的位置算列表落点（快捷栏/槽拖回列表时用）
    function updateTargetFromGhost() {
        if (!root.ghostInList()) {
            // ghost 在列表外（拖去固定栏 / 槽）：列表显示「移除后的样子」——
            // 源格之后整体前移，不留空位。落点用 -1 表示"不在列表"，
            // 松手时 commitDrop 也据此跳过列表内排序。
            root.dragTarget = -1
            return
        }
        const view = root.actionListRef
        if (!view)
            return
        const inScroll = view.mapFromItem(root, root.ghostX, root.ghostY)
        root.dragTarget = Actions.dropIndexAt(
            inScroll.x,
            inScroll.y + view.contentY,
            view.width,
            (root.availableActions || []).length,
            root.keyH,
            root.gap,
            actionListColumns)
    }

    // 计算落点：右上角槽 / 固定栏（三种拖动源共用）。
    // 固定栏不看「整块区域」，而是换算成插入位置 —— 拖动时才能显示松手后的样子。
    function updateDropTargets() {
        if (!quickBar) {
            root.dragOverSlot = false
            root.dragBarIndex = -1
            return
        }
        const barOrigin = quickBar.mapToItem(root, 0, 0)
        const slotLeft = barOrigin.x + quickBar.width - quickBar.btnW
        const slotTop = barOrigin.y + (quickBar.height - quickBar.btnW) / 2
        root.dragOverSlot =
            root.ghostX >= slotLeft && root.ghostX <= slotLeft + quickBar.btnW
            && root.ghostY >= slotTop && root.ghostY <= slotTop + quickBar.btnW

        const midLeft = barOrigin.x + quickBar.midX
        const inBand = !root.dragOverSlot
            && root.ghostY >= barOrigin.y
            && root.ghostY <= barOrigin.y + quickBar.height
            && root.ghostX >= midLeft
            && root.ghostX <= midLeft + quickBar.midW
        root.dragBarIndex = inBand
            ? Actions.quickBarInsertIndex(root.ghostX - midLeft,
                                          (root.quickBarActions || []).length,
                                          quickBar.slotW, quickBar.slotGap)
            : -1
    }

    function ghostInList() {
        const view = root.actionListRef
        if (!view)
            return false
        const inScroll = view.mapFromItem(root, root.ghostX, root.ghostY)
        return inScroll.x >= 0 && inScroll.x <= view.width
            && inScroll.y >= 0 && inScroll.y <= view.height
    }





    function finishDrag() {
        root.dragOwner = ""
        root.dragIndex = -1
        root.dragTarget = -1
        root.dragBarIndex = -1
        root.dragOverSlot = false
        if (root.actionListRef)
            root.actionListRef.interactive = true
        // 幽灵块淡出后再移除
        root.ghostFading = true
        ghostFadeTimer.restart()
    }

    function clearGhost() {
        root.ghostAction = null
        root.ghostFading = false
    }

    // 顶部快捷条的按钮（目前两个，后面可扩展）
    readonly property var quickBarItems: [
        {icon: "apps", action: "nav", kind: "nav"},
        {icon: "mic", action: "mic", kind: "slot"}
    ]

    // fcitx5 当前输入法
    signal imSwitchRequested()
    // 长按地球弹出的输入法选择器
    signal imListRequested()
    signal imCycleRequested()
    signal imSelected(string name)
    property bool imPickerOpen: false
    property var imList: []

    readonly property var rows: {
        const base = Layout.pageRows(page)
        return root.escSwap ? root.swapEscTilde(base) : base
    }

    // 把 \`~ 键换成 Esc，Fn 层的 Esc 换成 \`~（角落键位习惯）
    // Esc ↔ ` 对调的逻辑在 data.js（有单测）
    function swapEscTilde(layoutRows) {
        return Data.swapEscTilde(layoutRows)
    }
    // 当前页摊平后的键位列表：spaceEntry 与 Repeater 共用一份，避免每次算两遍
    readonly property var flatKeys: Layout.layoutFlat(page)
    // 候选 / 快捷条：候选来自 fcitx5 addon（inline-keyboard-status.json），没有候选时显示快捷键
    readonly property var candidates: root.fcitxCandidates
    readonly property string preedit: root.fcitxPreedit
    readonly property var shortcuts: Layout.demoShortcuts
    readonly property color fg: Theme.surfaceText
    // 顶部快捷条高度 = 圆形按钮直径（按钮填满这一行）；窗口按 KeyboardMetrics 传入
    property real quickH: Math.round(keyH * 0.78)

    // 动作表由插件设置提供（daemon 传进来）
    property var actionList: []
    // fcitx5 候选（daemon 从 inline-keyboard-status.json 读入）
    // 候选完整列表是否展开。状态由 card 自己持有（和 imPickerOpen 一样），
    // CandidateBar 通过 controller.candExpanded 读写，不经过窗口/daemon 的绑定链
    // ——那条链实测不可靠（card 根本没有 controller 之外的 daemon 引用）。
    property bool candExpanded: false
    // addon 报告的「还有下一页候选」。顶栏池只有 18 个，放得下不代表
    // 没有更多 —— 判断要不要展开按钮得看这个。
    readonly property bool hasMoreCandidates: root.fcitxHasMore
    // 候选栏实际显示了几个（CandidatePanel 要跳过这一段）
    readonly property int candFitCount: candBar ? candBar.fitCount : 0
    readonly property int candPoolLen: candBar ? candBar.poolLen : -1
    readonly property bool candBarOverflow: candBar ? candBar.hasOverflow : false
    // 候选栏放不下全部候选时才允许展开
    readonly property bool candOverflow: candBar ? candBar.hasOverflow : false
    // 展开要拿所有页的候选。card 没有 daemon 引用，不能用 controller.xxx，
    // 走信号一路传到 daemon（它才是持有 fcitx5 通道的那一层）。
    signal allCandidatesRequested()
    // daemon 收齐后下发到这里
    property var allCandidates: []
    // 候选栏直接用全量候选排列，所以「有候选但还没有全量」时就要拉。
    //
    // 不能用 onFcitxCandidatesChanged 驱动：QML 里 property var 存数组时，
    // 整个数组被替换**也不一定**触发 onChanged（实测这里就没触发过）。
    // 用派生布尔量做条件，它是由内容算出来的，变化可靠。
    readonly property bool needsAllCandidates:
        root.candidates.length > 0 && root.allCandidates.length === 0
    onNeedsAllCandidatesChanged: if (needsAllCandidates)
                                      root.allCandidatesRequested()
    onCandExpandedChanged: {
        if (candExpanded)
            root.allCandidatesRequested()
    }
    // 候选变少、全部塞进候选栏之后，展开页没有内容了，自动收起
    onCandOverflowChanged: if (!candOverflow) candExpanded = false
    property var fcitxCandidates: []
    // 当前输入法是否纯键盘布局（这类输入法没有候选，不显示候选栏）
    property bool fcitxImKeyboard: false
    // 还有没显示的候选（addon 算的，不是 hasNext）
    property bool fcitxHasMore: false
    // addon 给的输入法图标绝对路径（比托盘抓图可靠）
    property string fcitxImIcon: ""
    property string fcitxImLabel: ""
    property bool fcitxPreeditEmbedded: false
    property string fcitxPreedit: ""
    property bool fcitxVisible: false

    // 已放进固定位置的动作用户不应在列表里再看到一次
    // 列表可见动作：已在槽/快捷栏里的不重复显示
    // 第三个参数必须用「冻结后」的固定栏：松手后到数据回来之前，固定栏已经显示新顺序了，
    // 若这里还用旧的 quickBarActions，那个动作会同时在固定栏和列表里出现。
    // 但也不能用拖动中的 barDropPlan —— availableActions 同时是 Repeater 的 model，
    // 拖动中每帧变化就会重建 delegate，把拖动手势弄断。
    readonly property var availableActions:
        Actions.visibleActions(root.frozenList || actionList, slotActionId,
                               root.frozenBar || quickBarActions)

    // 动作当前状态：active（开着的开关）/ disabled（当前不可用）/ default。
    // 必须是**属性绑定**而不是函数：函数体里读的 avoidWindows/isFloating 不会被
    // QML 绑定跟踪，状态变了图标也不会重算（踩过：固定栏的激活态一直不亮）
    readonly property var actionStates: ({
        float: root.isFloating ? "active" : "default",
        avoid: root.isFloating ? "disabled" : (root.avoidWindows ? "active" : "default")
    })

    // ---- 拖动预览：编辑态显示「松手后会变成的样子」 ----
    // 固定栏最多放几个：按可用宽度算，另设 6 个的软上限免得挤成一排
    readonly property int quickBarCapacity: quickBar
        ? Math.max(1, Math.min(6, Math.floor((quickBar.midW + gap) / (quickBar.slotW + gap))))
        : 4

    // 落到固定栏的入参：拖动预览和松手落盘必须是同一份，所以只在这里构造
    function quickBarDropArgs(action, index, source, sourceIndex) {
        return {
            bar: root.quickBarActions,
            actionList: root.actionList,
            action: action,
            index: index,
            capacity: root.quickBarCapacity,
            slotActionId: root.slotActionId,
            source: source,
            sourceIndex: sourceIndex
        }
    }

    // 落在固定栏时的最终结果（预览和落盘共用 actions.js 的 planQuickBarDrop）
    readonly property var barDropPlan: {
        if (!(root.editing && root.dragActive && root.dragBarIndex >= 0 && root.ghostAction))
            return null
        return Actions.planQuickBarDrop(
            root.quickBarDropArgs(root.ghostAction, root.dragBarIndex,
                                  root.dragFrom, root.dragFromIndex))
    }

    // 调试用：用原始数组直接算一遍可见动作，和 availableActions 的绑定结果对照
    function debugVisibleCount() {
        return Actions.visibleActions(actionList, slotActionId, quickBarActions).length
    }

    // 松手后短暂保留落盘后的顺序：真实数据要等一个 IPC 往返才回到卡片，
    // 中间若用旧数组，位置会先跳回去、再动画到新位置（看起来就是"松手后又演了一遍"）
    property var frozenBar: null
    property var frozenList: null

    // 松手后固定栏的样子。注意：这里只用来**算位置**，绝不能拿它当 Repeater 的 model
    // —— Repeater 的 model 一换（拖动时每帧都可能变）就会销毁重建 delegate，
    // 拖动手势的 DragHandler 跟着死掉，endDrag 再也不触发，状态就卡住了。
    readonly property var quickBarResolved: Actions.quickBarViewActions({
        bar: root.quickBarActions,
        plan: root.barDropPlan,
        frozen: root.frozenBar,
        dragActive: root.dragActive,
        dragFrom: root.dragFrom,
        dragFromIndex: root.dragFromIndex
    })

    // 某个动作在「松手后的固定栏」里排第几；-1 = 它会被挤出去
    // 索引换算在 data.js（有单测）；QuickBar 通过 controller 调这一层
    function quickBarIndexFor(id) {
        return Data.quickBarIndexFor(root.quickBarResolved, id)
    }

    // 拖到固定栏时被挤出来的那个动作（列表里用幽灵块表示，不塞进 model）
    readonly property var listEjected: root.barDropPlan ? root.barDropPlan.ejected : null

    // 功能列表的列数（列表布局与落点计算共用）
    readonly property int actionListColumns: 4

    // 列表视图引用：动作列表拆成 ActionList 组件后，拖动落点计算仍需要它
    property var actionListRef: null

    // 空格键的位置（只有 page1 有），用来把输入法图标叠在空格正中间
    readonly property var spaceEntry: {
        if (page !== "page1")
            return null
        const list = root.flatKeys
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (e.key && e.key.k === "space")
                return e
        }
        return null
    }
    readonly property real spaceX: spaceEntry ? spaceEntry.col * (unit + gap) : 0
    readonly property real spaceY: spaceEntry ? spaceEntry.row * (keyH + gap) : 0
    readonly property real spaceW: spaceEntry
        ? spaceEntry.key.w * unit + (spaceEntry.key.w - 1) * gap : 0

    signal keyPressed(var keyData)
    // 点了第 index 个候选
    signal selectCandidateRequested(int index)
    // 修饰键的按下/松开（只有「按住才生效」模式用，daemon 里会过滤非修饰键）
    signal modifierPressed(var keyData)
    signal modifierReleased(var keyData)
    signal quickAction(string action)
    // 浮动模式拖把手用：开始拖 / 拖了多少（像素）
    signal dragStarted()
    // 动作顺序变了 / 槽里的动作变了（交由 daemon 持久化）
    signal orderChanged(var orderedActions)
    signal slotChanged(string actionId)
    signal dragMoved(real dx, real dy)

    // I18n.trFor 的上下文 id（= plugin.json 的 id），缺词条时回退英文原串
    readonly property string pluginId: "inlineKeyboard"

    // 插件翻译表由 PluginService 异步注册，晚于卡片构造（实测 onCompleted 时还没就绪）。
    // 用一个短轮询把它变成 root.localeVersion 的变化，让所有 tr() 绑定重算；
    // 不用 Connections 监听 pluginTranslationsChanged —— 在这里收不到。
    property int localeVersion: 0
    property int translationPollCount: 0

    Timer {
        id: translationPoll
        interval: 100
        repeat: true
        running: root.localeVersion === 0 && root.translationPollCount < 100
        onTriggered: {
            root.translationPollCount++
            const tables = (typeof I18n !== "undefined" && I18n) ? I18n.pluginTranslations : null
            if (tables && tables[root.pluginId])
                root.localeVersion = 1
        }
    }

    // 用户可见文案统一走插件翻译表（translations/<locale>.json），缺词条回退英文原串
    function tr(term) {
        const version = root.localeVersion      // 让调用处的绑定跟随版本重算
        if (typeof I18n === "undefined" || !I18n || !I18n.trFor)
            return term
        return I18n.trFor(root.pluginId, term)
    }

    // 键位 → 修饰键状态：映射规则在 modifiers.js（有单测），这里只查表
    function modifierStateFor(keyData) {
        const name = Modifiers.modifierNameFor(keyData)
        return name === "" ? 0 : (root.modifierStates[name] || 0)
    }

    width: unit * Layout.rowUnits + gap * (Layout.rowUnits - 1) + pad * 2

    // 卡片高度**固定**：一律按主键区的行数算。
    //
    // 不能用 rows.length —— 那是「当前页」的行数，切到表情页（0 行）、
    // 功能页时键盘会跟着变高变矮，看着像在跳。
    // 也不用 (showHandle ? handleH : 0) —— 浮动模式无把手时高度会少一截，
    // 停靠/浮动切换时同样会跳。把手高度永远占着，showHandle 只控制可见性。
    //
    // 候选栏和快捷栏叠在同一个 topArea 里（二选一覆盖），不额外占高度，
    // 所以这里也不能加 candH。
    readonly property int layoutRowCount: Layout.pageRows("page1").length
    height: pad * 2 + quickH + gap
            + layoutRowCount * keyH + Math.max(0, layoutRowCount - 1) * gap
            + handleH

    radius: Theme.cornerRadius
    // 卡片底跟 DMS 设置页同色（surface），透明度仍由插件设置控制
    color: Theme.withAlpha(Theme.surface, bgOpacity)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.7)

    // 透明度调整时，键盘外围画一圈提示边框
    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: "transparent"
        border.width: 2
        border.color: Theme.primary
        opacity: root.mode === "transparency" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        z: 200
    }

    Column {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.gap

        // ---------------- 顶部区域：快捷栏 / 候选栏二选一 ----------------
        // 候选出现时覆盖快捷栏（同一块高度，不是上下共存）。
        // 用 Item 叠放而不是 Column 两行：键盘总高度不能因为出现候选而变化。
        Item {
            id: topArea
            width: parent.width
            // 快捷栏用 quickH、候选栏内部用 candH，取较大值才不会挤出边界
            height: Math.max(root.quickH, root.candH)

            // 快捷栏（独立组件）
            QuickBar {
                id: quickBar
                controller: root
                anchors.fill: parent
                // 用 opacity 而不是 visible：visible:false 期间内部几何不重算，
                // 切回主页面时槽会被摆到错误的键位上（踩过）
                opacity: (root.page === "emoji" || root.showCandBar) ? 0 : 1
                enabled: root.page !== "emoji" && !root.showCandBar
            }

            // 候选栏：盖在快捷栏上面
            CandidateBar {
                id: candBar
                controller: root
                anchors.fill: parent
                visible: root.showCandBar
                z: 10
            }

            // 表情页：左上角一个 X 返回（顶掉快捷栏和右上角的槽）
            Rectangle {
                visible: root.page === "emoji"
                anchors.left: parent.left
                anchors.top: parent.top
                width: root.quickH
                height: root.quickH
                radius: width / 2
                color: Theme.surfaceContainer

                DankIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: Math.round(root.quickH * 0.45)
                    color: Theme.withAlpha(root.fg, 0.85)
                }

                TapHandler {
                    onTapped: root.page = "keys"
                }
            }
        }

        // ---------------- 主区：键区 / 功能列表 ----------------
        // 两个子页共用同一块高度，靠 visible 切换，外层高度恒定
        Item {
            id: mainArea
            width: parent.width
            // 展开候选列表时整块键区让位：它是「换页」不是「盖一层」，
            // 按键必须真正隐藏，否则下面的按键还能被点到。
            visible: !root.candExpanded
            // 高度取所有页里最多的行数：切到空页（表情）也不会让键盘缩水
            height: {
                let lines = root.rows.length
                const main = Layout.pageRows("keys").length
                if (main > lines)
                    lines = main
                return lines * root.keyH + Math.max(0, lines - 1) * root.gap
            }

            // ---- 键区 ----
            KeyGrid {
                controller: root
                anchors.fill: parent
                visible: root.mode === "keys"
            }

            // ---- 透明度调整面板 ----
            TransparencyPanel {
                id: transparencyArea
                controller: root
                anchors.fill: parent
                visible: root.mode === "transparency"
            }

            // ---- 快捷功能列表 ----
            ActionList {
                id: functionsArea
                controller: root
                anchors.fill: parent
                visible: root.mode === "functions"
            }
        }

        // ---------------- 底部把手条 ----------------
        BottomBar {
            controller: root
        }
    }

    // 拖动提交后的延迟收尾（Qt.callLater 会丢 root 上下文，用 Timer 代替）
    Timer {
        id: dragDeferTimer
        interval: 16
        onTriggered: {
            root.reenableAnim()
            root.finishDrag()
        }
    }

    // 冻结窗口：够一次 IPC 往返即可，太长会盖住别的变化
    Timer {
        id: freezeTimer
        interval: 220
        onTriggered: {
            root.frozenBar = null
            root.frozenList = null
        }
    }

    Timer {
        id: ghostFadeTimer
        interval: 200
        onTriggered: root.clearGhost()
    }

    // 兜底清理：拖动结束后若状态没复位（delegate 重建会吞掉 activeChanged），强制清掉
    Timer {
        id: dragCleanup
        interval: 150
        repeat: true
        running: root.dragActive || root.ghostAction !== null
        onTriggered: {
            if (root.dragActive)
                return
            root.dragIndex = -1
            root.dragTarget = -1
            root.ghostAction = null
            root.dragOverSlot = false
            if (root.actionListRef)
                root.actionListRef.interactive = true
        }
    }

    // ---------------- 展开的候选列表页 ----------------
    // 暴露给 daemon 的调试 IPC（翻页验证用）
    readonly property var candidatePanel: candPanelItem

    CandidatePanel {
        id: candPanelItem
        controller: root
    }

    // ---------------- 拖动中的浮动块 ----------------
    // 放在卡片根部才不会被列表的 clip 裁掉
    DragGhost {
        id: dragGhost
        controller: root
    }

    // ---------------- 输入法选择器（长按地球） ----------------
    ImPicker {
        id: imPicker
        controller: root
    }
}
