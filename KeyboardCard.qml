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
import "layouts/resize.js" as Resize

// 键盘主体：顶部快捷条 + 候选/快捷栏 + 键区（或功能列表） + 底部把手条
Rectangle {
    id: root

    // 尺寸（由窗口按屏幕宽度/用户设置算好后传进来）
    property real unit: 63
    property real keyH: 64
    property real gap: 6
    property real pad: 8
    property real candH: 44
    // 和顶部动作固定栏同高（quickH），图标也按它的比例
    property real handleH: Math.round(root.quickH)
    property bool showHandle: true
    property bool dragEnabled: false
    // 长按自动重复的间隔（毫秒），由设置页配置
    property int repeatInterval: 60
    // 候选栏整行的开关：显示条件看**这个输入法在 fcitx5 下会不会弹候选窗**，
    // 不是当前有没有词。纯键盘布局（keyboard-us 这类）没有候选能力，不显示；
    // rime 的中英文模式都会出候选，所以即使这一刻 items 还空着也占位。
    //
    // 注意写成一行：QML 的 JS 在换行处会插分号，多行表达式会被截断成
    // 「第一行求值 + 第二行变成独立语句」，值悄悄算错（踩过）。
    property bool showCandBar: false

    // 状态
    property bool fnActive: false
    // Esc 与 ` 对调（设置项）
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定）
    property var modifierStates: ({})
    property string page: "page1"
    // 表情页的两级选择：段（表情 / 符号）+ 分类（"all" 或分组 id）。
    // 放在卡片上是因为顶部分类条和中间的网格要读同一份状态。
    property string emojiSegment: "emoji"
    property string emojiCategory: "all"
    // 点候选上屏：把索引写进 $XDG_RUNTIME_DIR/inline-keyboard-select，
    // fcitx5 的 inline-keyboard-status addon 轮询到后直接调 CandidateWord::select()——
    // 这是 fcitx5 内部的真正选词入口，等价于用户按了选择键。
    // 选词逻辑在 daemon（UI 只负责报告"点了第几个"）
    // 换页请求走和键位同一个入口（keyPressed → 窗口 → daemon.handleKey）。
    // 卡片里的 page 是**绑定**到 daemon 的，直接赋值会把这个绑定掐断，
    // 之后 daemon 再换页卡片就收不到了（旧代码里表情页的 X 就是这么写的）。
    function goPage(target) {
        root.keyPressed({k: "page", to: target})
    }

    // 最近一次选词：元素是「传进 addon 的 index」和「此刻该下标对应的词」。
    // 列表是切片出来的，显示位置和原始下标不是一回事，所以要对照着看。
    // 用属性而不是 console.log：dms 里 console.log 不一定进 journal。
    property string lastSelectInfo: ""

    function selectCandidate(index) {
        const item = root.candListModel[index]
        root.lastSelectInfo = "idx=" + index
            + " word=" + (item && item.t !== undefined ? item.t : "?")
            + " at=" + Date.now()
        root.selectCandidateRequested(index)

        // 选词后立刻重拉全量并立刻重排，两条 debounce/throttle 都绕过。
        //
        // 那 800ms 是给打字用的（rime 的 BulkCandidateList 懒加载，取一次
        // 要跨页生成）；选词是明确的用户动作，而且列表页本来就不会用来
        // 连续打字，没有「连续输入」要合并，等它只会让列表明显滞后。
        if (root.candListOpen) {
            root.recentSelect = true
            selectWindowTimer.restart()
            candReloadTimer.stop()
            root.candLoading = true
            root.allCandidatesRequested()
            candLoadGuard.restart()
            // 先把当前状态立刻刷上去；addon 回包后 candDataSeq 会再 ++ 一次，
            // 那次走的就是下面的 recentSelect 分支，同样是立即的
            if (candListPanel)
                candListPanel.forceRelayout()
        }
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
    // 透明度面板改值只落在卡片上（绑定被打断），要往上抛给 daemon 才能保存
    signal opacityAdjusted(real bg, real key)
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
    // 语音输入是否在录音（daemon 传下来，决定顶部是否切到语音行）
    property bool voiceActive: false
    // 语音模式：只留顶部语音行。由 daemon 传下来（daemon 负责切浮动），
    // 卡片只负责按它隐藏主区和底栏。
    property bool voiceMinimal: false
    // vinput 是否可用：没装时语音动作禁用，键盘其它功能不变
    property bool voiceAvailable: false

    // 左键点击 → 交给 daemon 切模式
    function toggleVoiceMinimal() {
        root.voiceMinimalRequested()
    }

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
    // 展开状态下，候选一有变化就重拉全量。
    //
    // debounce 350ms：跨页遍历 rime 的候选挺慢（懒加载，取第 N 个要先生成
    // 前面的），每敲一个键都拉会把 fcitx5 的事件循环堵住，打字一格一格跳。
    property var fcitxCandidates: []
    // 调试注入的假候选（dms ipc call inlineKeyboard debugCand "一,二,三"）。
    // 终端这类不支持 text-input 的窗口里 fcitx5 不产生候选，
    // 没有它就没法把候选栏调出来看布局。非空时优先于真实候选用。
    property var debugCandItems: []
    // 候选列表页是否展开。展开时键区让位（真换页，不是盖一层），
    // 否则下面的按键还会被点到。
    property bool candListOpen: false
    // 候选面板引用（调试用）
    property var candListPanel: null
    // 候选内容变化计数（FcitxBridge.candRevision 传下来）
    property int candRevision: 0
    onCandRevisionChanged: {
        if (!root.candListOpen)
            return
        if (root.recentSelect) {
            // 选词刚发生：这是选词引起的候选变化，立刻处理
            candReloadTimer.stop()
            root.allCandidatesRequested()
            if (candListPanel)
                candListPanel.forceRelayout()
            return
        }
        // 普通打字：走 800ms，合并连续的按键
        candReloadTimer.restart()
    }

    // 选词窗口：600ms 后恢复正常（覆盖 addon 回包 + 一次状态推送）
    Timer {
        id: selectWindowTimer
        interval: 600
        repeat: false
        onTriggered: root.recentSelect = false
    }
    // 全量候选（窗口从 FcitxBridge 转发下来）
    property var allCandidates: []
    // 正在等 addon 回包
    property bool candLoading: false
    // 「刚选过词」窗口：选词是明确动作，列表页此时也不会再打字，
    // 所以这段时间里候选变化要立刻处理，不能走 800ms 的打字 debounce。
    property bool recentSelect: false
    // 主键区行数，候选列表页的滚动区高度按它算
    readonly property int keyRowCount: Layout.pageRows("page1").length

    // 特殊键的表现形式（见 layouts/special-keys.js）
    property string specialKeyStyle: "full"
    property string winKeyStyle: "mod"
    property string winKeyCustomIcon: ""

    // 调整大小面板：预览尺寸 / 名义尺寸 / 屏幕尺寸 / 停靠是否铺满
    property real resizeW: 1050
    // 正在拖的把手（"n"/"s"/"e"/"w"…，空串=没在拖）。
    // 预览框必须靠它决定钉住哪条边：原来 x 死写居中，拖 w 时两边一起扩。
    property string resizeHandle: ""
    property real resizeH: 444
    property real baseKbWidth: 1050
    property real baseKbHeight: 444
    property real screenW: 1920
    property real screenH: 1080
    property bool dockFill: true
    signal resizeCommitRequested()
    // 松手落盘时用：键盘尺寸变成新值后，卡片位置要补偿多少，
    // 才能让「拖的那条边」的对侧保持不动。拖动过程中不移动键盘。
    signal resizeOriginShift(real dx, real dy)
    signal resizeCloseRequested()
    signal resizeCancelRequested()
    signal resizeResetRequested()
    signal resizeFillToggleRequested()
    // 换模式的请求：不能在子组件里直接写 card.mode —— 那是 daemon 的
    // `mode: root.mode` 绑定，直接赋值会把绑定打断，之后 daemon 再怎么改
    // mode 卡片都不会跟着变（「点了调整大小没反应」就是这么来的）
    signal modeChangeRequested(string mode)

    // 候选列表页的数据源：真实全量候选优先；调试注入的 {i,t} 兜底
    // 调试候选的 {i,t} 形态缓存：debugCandItems 每变一次才重建，
    // 不用每次读 candListModel 都 map 一遍（1000 词就是 1000 个对象）。
    property var debugCandModel: []

    // addon 推的顶部候选也是纯字符串数组，同样要缓存成 {i,t}，
    // 否则 candListModel 每次求值都要 map 一遍（18 个对象/次）。
    property var fcitxModel: []

    onDebugCandItemsChanged: {
        debugCandModel = root.debugCandItems.map(
            (t, n) => ({ i: n, t: String(t) }))
        root.recomputeCandBar()
    }

    onFcitxCandidatesChanged: {
        fcitxModel = root.fcitxCandidates.map(
            (t, n) => ({ i: n, t: String(t) }))
        // 候选栏的数据源就是 fcitxModel，它一变就要重算容量 + 重排。
        // 以前这两件事挂在 candListModel 上，但那个属性现在只服务列表页
        // （全量懒加载），打字时的实时更新根本到不了它。
        root.recomputeCandBar()
        root.candDataSeq++
    }

    // 候选**列表页**的数据源：全量优先。
    //
    // 注意它不能拿来喂候选栏：allCandidates 是懒加载的（只有展开列表时
    // 才拉一次），一旦它非空，items 的实时更新就再也传不进来了 ——
    // 这就是「输入长串 → 展开 → 选词 → 收起后候选栏不更新」的 100% 复现。
    // 候选栏走下面的 candBarSource。
    readonly property var candListModel: {
        if (root.allCandidates.length > 0)
            return root.allCandidates
        if (root.debugCandModel.length > 0)
            return root.debugCandModel
        return root.fcitxModel
    }

    // 候选**栏**的数据源：永远用 items（addon 每 40ms 推的实时顶部候选）。
    // 调试注入时用调试数据。
    readonly property var candBarSource: {
        if (root.debugCandModel.length > 0)
            return root.debugCandModel
        return root.fcitxModel
    }

    // 候选栏能装下 candListModel 的前几项。
    //
    // 语义：候选栏和候选列表是**同一个列表的两段** —— 前面装进顶栏，
    // 剩下的进列表页，两边不重复。所以容量必须按同一份数据算，
    // 而且要用列表**前面的项**去量宽度（而不是拿一个假想的平均数）。
    //
    // 不能写成 property 绑定：量文字要改 measure.text，而结果又依赖
    // measure.advanceWidth，Qt 会判定成绑定循环（实测狂刷 Binding loop）。
    property int candBarCount: 0

    // 顶栏词区的可用宽度：卡片宽减去两侧内边距，再减右侧那一列
    readonly property real candBarAvail:
        Math.max(0, root.width - root.pad * 2 - (root.unit + root.gap))

    TextMetrics {
        id: candMeasure
        font.pixelSize: Math.round(root.keyH * 0.42)
        font.weight: Font.Normal
    }

    function recomputeCandBar() {
        const list = root.candBarSource
        if (!list || list.length === 0 || root.candBarAvail <= 0) {
            root.candBarCount = 0
            return
        }
        const avail = root.candBarAvail
        // 首项最多占候选栏的三分之二，再长就省略前面（见 CandidateBar）
        const firstMax = avail * 2 / 3
        let used = 0
        let n = 0
        for (let i = 0; i < list.length; i++) {
            const t = list[i] && list[i].t !== undefined
                      ? String(list[i].t) : String(list[i] || "")
            candMeasure.text = t
            let w = candMeasure.advanceWidth + root.unit * 2 / 3 + root.gap
            if (i === 0 && w > firstMax)
                w = firstMax
            if (used + w > avail)
                break
            used += w
            n++
        }

        root.candBarCount = n
        // 只有这里才切一次数组，下游读的是稳定引用
        root.candBarItems = n <= 0 ? [] : list.slice(0, n)
        // 列表页从候选栏之后开始，避免和顶栏重复。
        // 两边数据源不同（栏是实时 items，列表是懒加载的全量），但顺序
        // 由 rime 保证一致：全量的前 n 个就是 items 的前 n 个。
        //
        // 全量还没回来的这一小段（展开后几十毫秒）先留空：回落数据源是
        // 顶部那 18 项 items，用它渲染只会显示残缺的十来个，
        // 等全量到了再变长 —— 看起来就是「要展开两次才完整」。
        const waiting = root.candListOpen && root.candLoading
            && root.allCandidates.length === 0
        root.candListItems = waiting ? []
            : (n >= root.candListModel.length
               ? [] : root.candListModel.slice(n))
    }

    onWidthChanged: recomputeCandBar()
    onUnitChanged: recomputeCandBar()
    onGapChanged: recomputeCandBar()
    // 高度变了 keyH 就变，候选测量的字号跟着变（candMeasure.font 依赖 keyH），
    // 容量必须重算 —— 否则拖高键盘后候选栏仍按旧字号排版，出现早省略
    onKeyHChanged: recomputeCandBar()
    Component.onCompleted: recomputeCandBar()

    // 候选栏显示前一段
    // 候选栏实际显示的项，以及列表页的输入（不含顶栏部分）。
    // 都在 recomputeCandBar() 里一次性存好：slice 每次调用都会新建数组，
    // 让下游 Repeater 误以为数据全换了，跟着重建 delegate。
    property var candBarItems: []
    property var candListItems: []
    readonly property var candBarSlice: candBarItems

    // 候选列表页显示后一段（不含顶栏已有的，避免重复）。
    //
    // 只切「现在要画的那一窗」，不是整个后段：候选页每换一次候选都会
    // 重建 Repeater，切 2000 个再截断比切 400 个慢三倍多
    // （实测展开状态连续换候选：57ms -> 预计 20ms 以内）。
    // candListTotal 给面板算滚动位置和「还有多少」用。
    readonly property int candListTotal:
        Math.max(0, root.candListModel.length - Math.max(0, root.candBarCount))

    // 候选数据的版本号：candListModel 的任何来源变了都 ++。
    // 不能只靠 candRevision（那是 FcitxBridge 的推送计数，debugCand
    // 这种直接改属性的路径根本不经过它，面板就永远不重排）。
    property int candDataSeq: 0

    onCandListModelChanged: {
        // 顺序很重要：先重算切分，再发版本号。反过来的话面板收到
        // candDataSeq 变化时 candListSlice 还是旧的，要等下一个节流窗口
        // 才纠正 —— 表现就是「展开两次才对」。
        root.recomputeCandBar()
        root.candDataSeq++
    }

    // 全量回来了就结束载入态。之前只有 1200ms 的超时兜底会复位，
    // 数据早就到了却还在显示「载入中」。
    onAllCandidatesChanged: {
        if (root.allCandidates.length > 0)
            root.candLoading = false
    }

    // 预编辑字符串一消失，列表页就自动收起。
    //
    // 判据只看 fcitxPreedit：那是 fcitx5 当前正在组词的那串（拼音/预编辑），
    // 它空掉就意味着这一轮输入结束了，列表再留着也没有内容可变。
    // 不看候选项数量——rime 提交后候选可能还剩一页残留，但用户已经选完了。
    //
    // 80ms 防抖：连续选字时 rime 可能刚清空又立刻给出下一串，
    // 期间只要 preedit 重新有内容，条件就不成立、定时器不触发。
    // 调试注入不算结束，否则 debugCand 模式下 fcitxPreedit 恒空、一展开就被收起。
    readonly property bool candsFinished:
        candListOpen
        && fcitxPreedit === ""
        && debugCandItems.length === 0

    onCandsFinishedChanged: if (candsFinished) autoCollapseTimer.restart()

    Timer {
        id: autoCollapseTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (!root.candsFinished)
                return
            root.candListOpen = false
            root.recentSelect = false
        }
    }

    // 候选列表页拿全量后段。渲染量由 CandidatePanel 自己虚拟化控制
    // （只实例化可视行），所以这里不需要再切窗口。
    readonly property var candListSlice: root.candListItems

    // 展开 / 收起候选列表页。打开时顺手要一次全量候选：
    // addon 只在收到 expand 时才遍历 BulkCandidateList（rime 懒加载，
    // 取第 7 个得先生成下一页，有成本），不能每次状态推送都拉。
    function toggleCandList() {
        root.candListOpen = !root.candListOpen
        if (root.candListOpen) {
            root.candLoading = true
            root.allCandidatesRequested()
            // addon 正常几十毫秒就回包；这里只是兜底，避免没装 addon 时
            // 面板永远停在「载入中」
            candLoadGuard.restart()
        } else {
            candLoadGuard.stop()
            root.candLoading = false
        }
    }

    // 展开状态下候选变了 → 重新拉全量。
    // 加 debounce：打字时每次按键都会 ++，等停手再拉，
    // 否则每打一个字就遍历一遍 BulkCandidateList（rime 懒加载，有成本）。
    Timer {
        id: candReloadTimer
        // 800ms：rime 的 BulkCandidateList 是懒加载，取一次要跨页生成，
        // 展开状态下每打几个字就重拉太贵（实测是主要的 CPU 抖动来源）。
        interval: 800
        repeat: false
        onTriggered: {
            if (root.candListOpen) {
                root.candLoading = true
                root.allCandidatesRequested()
                candLoadGuard.restart()
            }
        }
    }

    Timer {
        id: candLoadGuard
        interval: 1200
        repeat: false
        onTriggered: root.candLoading = false
    }

    signal allCandidatesRequested()
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
        avoid: root.isFloating ? "disabled" : (root.avoidWindows ? "active" : "default"),
        // 没装 vinput 就是禁用态；装了也是普通态 ——
        // 语音是否在录由语音行自己表达，动作图标不需要激活态
        mic: root.voiceAvailable ? "default" : "disabled"
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

    // 功能列表的列数（列表布局与落点计算共用）。
    // 由键盘宽度决定：按「一格至少能放下图标 + 四五个汉字」的最小宽度去排，
    // 宽键盘多排几列、窄键盘少排几列。写死 4 列时窄键盘字被挤成省略号、
    // 宽键盘又浪费一片空白。
    readonly property real actionMinCellW: 240
    readonly property int actionListColumns: Math.max(2,
        Math.floor((root.width - root.pad * 2 + root.gap)
                   / (root.actionMinCellW + root.gap)))

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
    // 表情 / 符号上屏：卡片只负责报「点了哪个字符」，
    // 真正怎么提交（addon commit / 剪贴板）由 daemon 决定。
    signal textCommitRequested(string text)
    // 点了第 index 个候选
    signal selectCandidateRequested(int index)
    // 修饰键的按下/松开（只有「按住才生效」模式用，daemon 里会过滤非修饰键）
    signal modifierPressed(var keyData)
    signal modifierReleased(var keyData)
    signal quickAction(string action)
    signal voiceMinimalRequested()
    // 语音行里两个按钮的点击请求：卡片自己不处理，转发给窗口 → daemon。
    // 之前 VoiceBar 直接调 controller.voiceMicPressed()，但卡片没有这个方法，
    // 点了就抛 ReferenceError，表现就是「点了没反应」。
    signal voiceMicRequested()
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
    // 和 Column 的结构逐项对齐，一项都不能少：
    //   pad | topArea | gap | 键区 | BottomBar
    // 底部把手行上下都不留白（贴键区、贴卡片底），所以只有一个顶部 pad、
    // 一段 gap，把手前那段和底部 pad 都没有。
    // topArea 用的是 max(quickH, candH)（候选栏可能比快捷栏高），
    // 这里也必须用同一个表达式，否则 Column 内容比卡片高、最后一项被挤出去。
    height: pad + Math.max(quickH, candH) + gap
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
        // 底部不留 pad：把手行要贴到卡片底边
        anchors.bottomMargin: 0
        // 间距改由显式 spacer 控制 —— Column 的 spacing 对所有子项一律生效，
        // 没法只去掉「键区 ↔ 把手」那一段。
        spacing: 0

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
                opacity: (root.page === "emoji" || root.showCandBar
                          || root.voiceActive) ? 0 : 1
                enabled: root.page !== "emoji" && !root.showCandBar && !root.voiceActive
            }

            // 语音行：录音时占掉这一整行，优先级 语音 > 候选 > 功能
            VoiceBar {
                id: voiceRow
                controller: root
                anchors.fill: parent
                // 语音模式下即使暂停也要留在屏幕上 —— 否则麦克风一进未激活态
                // 整行就没了，用户看不到「点它可以继续」这个提示
                visible: root.voiceActive || root.voiceMinimal
                z: 20
            }

            // 候选栏：盖在快捷栏上面。
            // 表情页不显示：那一行要留给分类，而且预编辑/候选在表情页上没意义，
            // 候选栏盖过去还会把左上角的返回 X 压住（踩过，X 点不到）。
            CandidateBar {
                id: candBar
                controller: root
                anchors.fill: parent
                visible: root.showCandBar && root.page !== "emoji" && !root.voiceActive
                z: 10
            }

            // 表情 / 符号页的分类条：占掉快捷栏那一行（快捷栏此处已淡出）
            EmojiCategoryBar {
                id: emojiCats
                controller: root
                anchors.fill: parent
                visible: root.page === "emoji"
            }
        }

        // ---------------- 主区：键区 / 功能列表 ----------------
        // 顶栏与键区之间的留白（把手行那边不加）
        Item {
            width: 1
            height: root.gap
        }

        // 两个子页共用同一块高度，靠 visible 切换，外层高度恒定
        Item {
            id: mainArea
            width: parent.width
            // 展开候选列表时整块键区让位：它是「换页」不是「盖一层」，
            // 按键必须真正隐藏，否则下面的按键还能被点到。
            // 高度取所有页里最多的行数：切到空页（表情）也不会让键盘缩水
            // 行数和卡片高度公式用同一个来源（layoutRowCount = 主键区行数），
            // 这样 Column 各项之和正好等于 card height，底部不会多出一截
            height: root.layoutRowCount * root.keyH
                    + Math.max(0, root.layoutRowCount - 1) * root.gap

            // ---- 候选列表页 ----
            // 常驻实例 + 切可见性，不用 Loader 的 active 来回开关：实测反复
            // 展开/收起会在销毁那一刻把内存冲到 6GB 并搞崩 qs —— 大子树的
            // 销毁/重建比一直持有贵得多。实际实例化数量由内部的 shownCount
            // 控制（默认一屏 60 项），所以「常驻」不等于把上千个 delegate 都建出来。
            CandidatePanel {
                id: candListPanel
                Component.onCompleted: root.candListPanel = candListPanel

                // 度量（unit/keyH/gap/rowCount）和候选数据全从卡片拿，
                // 漏了这一行会导致 unit/gap 取默认兜底值，列表宽度算错
                controller: root

                anchors.fill: parent
                visible: root.candListOpen
                // 收起时把渲染量归零，避免隐藏状态下仍持有几百个 delegate
                shownCountOverride: root.candListOpen ? -1 : 0
            }

            // ---- 键区 ----
            KeyGrid {
                controller: root
                anchors.fill: parent
                // resize 模式下键区要留着：遮罩半透明盖在上面，
                // 底下必须是真实的键盘主页面
                visible: (root.mode === "keys" || root.mode === "resize")
                         && root.page !== "emoji"
                         && !root.candListOpen
            }

            // ---- 表情 / 符号页 ----
            EmojiPanel {
                controller: root
                anchors.fill: parent
                visible: root.mode === "keys" && root.page === "emoji"
                         && !root.candListOpen
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
        // 放在 Column 末尾：它高度是 handleH、和卡片高度公式里的同一项，
        // Column 各子项加起来正好等于 card height，不需要额外让位也不需要贴底。
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

    // ---------------- 调整大小面板 ----------------
    //
    // 半透明遮罩压暗整个键盘（底下仍是键盘主页面），上面按当前尺寸画一个框，
    // 框的四边 + 四角是拖拽把手，中心是铺满/重置/取消/确定。框只是预览，
    // 键盘本身不动，确认才落盘。
    Item {
        id: resizeArea
        anchors.fill: parent
        visible: root.mode === "resize"
        // 盖在把手条（z 200）和所有页之上
        z: 300

        // 把手的**命中区**厚度固定，不跟键盘尺寸走。
        // 原来用 root.handleH（= keyH × 0.75），键盘一调大调小，可拖区域跟着
        // 变粗变细，手感完全不一样 —— 而用户是在调整尺寸的过程中拖它，
        // 等于一边拖一边改命中区，非常难用。视觉线条长度仍随框走。
        readonly property real grip: 46

        // 停靠且铺满时宽度没得调 → 只剩顶边；否则按模式给对应把手
        // 三个方向：上、左、右。
        //
        // 没有下方把手：底部那一行是「拖动改键盘位置」的把手，两个手势叠在
        // 同一个位置会互相抢；键盘下沿又贴着屏幕底或紧邻应用内容，往下拉
        // 本来也没什么意义。去掉后底部只负责移动位置。
        //
        // 也没有四角：L 形在角上要么和描边糊成一团、要么缩到看不清。
        readonly property var handles: {
            if (!root.isFloating && root.dockFill)
                return ["n"]                      // 已水平铺满，只能调高度
            return ["n", "e", "w"]
        }

        // 遮罩：整体键盘背景色的 50%
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.surface, 0.5)
            radius: Theme.cornerRadius

            // 吞掉点击：下面看得见但点不到
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }
        }

        // 框：尺寸就是松手后的键盘大小
        Rectangle {
            id: resizeFrame
            // 目标尺寸（不含描边内缩）
            readonly property real outerW: (!root.isFloating && root.dockFill)
                ? resizeArea.width
                : Math.round(root.resizeW)
            // resizeH 是从窗口拖出来的名义高度，仍含底部 pad 和把手前的 gap；
            // 卡片实际比它矮这两项，预览框要跟着矮，否则框比卡片高出一截。
            readonly property real outerH: Math.round(root.resizeH)
                                           - root.pad - root.gap
            // 描边宽度：按键高取比例，比边框线粗一档才看得出是「可拖区域」
            readonly property real bw: Math.max(4, Math.round(root.keyH * 0.07))

            // 矩形按半个描边内缩：内层描边骑在自己的边界上，
            // 内缩后外沿正好压在 outerW/outerH 这条线上，全部朝内长。
            //
            // 水平定位分两种情况：
            //   停靠模式：键盘本来就水平居中，拖左右必须**两边一起收/放**
            //             （planResize 的 symmetric 已把宽度按 2× 位移算），
            //             所以这里的框也要保持居中。
            //   浮动模式：拖哪边只动哪边，框要钉住**正在拖的那条边**的对侧
            //             （拖 w → 右边界不动，拖 e → 左边界不动）。
            // 之前一刀切钉对侧，把停靠的左右联动弄没了。
            readonly property bool symmetricX: !root.isFloating
                && (root.resizeHandle === ""
                    || root.resizeHandle === "e"
                    || root.resizeHandle === "w")
            x: Math.round(symmetricX
                          ? (resizeArea.width - outerW) / 2
                          : (root.resizeHandle.indexOf("w") >= 0
                             ? resizeArea.width - outerW : 0)) + bw / 2
            y: Math.round(root.resizeHandle.indexOf("n") >= 0
                          ? resizeArea.height - outerH : 0) + bw / 2
            width: Math.max(0, outerW - bw)
            height: Math.max(0, outerH - bw)
            color: "transparent"
            radius: Theme.cornerRadius

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: resizeFrame.bw
                border.color: Theme.primary
                radius: Math.max(0, Theme.cornerRadius - resizeFrame.bw / 2)
            }
        }

        // 把手
        Repeater {
            id: handleRepeater
            model: resizeArea.handles

            delegate: Item {
                id: handleItem
                required property var modelData

                readonly property string h: modelData
                readonly property real g: resizeArea.grip
                readonly property real fx: resizeFrame.x - resizeFrame.bw / 2
                readonly property real fy: resizeFrame.y - resizeFrame.bw / 2
                readonly property real fw: resizeFrame.outerW
                readonly property real fh: resizeFrame.outerH
                readonly property bool horizontal: h === "n" || h === "s"
                readonly property bool vertical: h === "w" || h === "e"
                // 边把手只取中间一段，整条会和描边糊在一起
                readonly property real barLen: Math.min(200, Math.max(60,
                    (horizontal ? fw : fh) * 0.3))

                // 命中区**完整落在框内**，不越过描边 —— 跨出去的部分在视觉上
                // 就是一条悬在框外的红线。居中用把手实际长度 barLen，不能用厚度 g。
                x: h === "w" ? fx
                 : h === "e" ? fx + fw - g
                 : fx + fw / 2 - barLen / 2
                y: h === "n" ? fy
                 : h === "s" ? fy + fh - g
                 : fy + fh / 2 - barLen / 2
                width: horizontal ? barLen : g
                height: vertical ? barLen : g

                Rectangle {
                    anchors.centerIn: parent
                    width: handleItem.horizontal ? parent.width : 6
                    height: handleItem.vertical ? parent.height : 6
                    radius: 3
                    color: Theme.primary
                }

                DragHandler {
                    target: null
                    cursorShape: handleItem.horizontal ? Qt.SizeVerCursor
                        : Qt.SizeHorCursor

                    property real startW: 0
                    property real startH: 0

                    onActiveChanged: {
                        if (active) {
                            startW = root.resizeW
                            startH = root.resizeH
                            root.resizeHandle = handleItem.h
                        } else {
                            // 松手即生效：把当前预览尺寸写进设置，键盘当场变成新大小。
                            // 尺寸变了但位置不动的话，卡片会继续锚在左上角 ——
                            // 拖左边却看到右边在长。这里把差值补进位置：
                            //   拖 w → 左边界左移 (startW - newW)
                            //   拖 n → 上边界上移 (startH - newH)
                            const dx = handleItem.h.indexOf("w") >= 0 ? startW - root.resizeW : 0
                            const dy = handleItem.h.indexOf("n") >= 0 ? startH - root.resizeH : 0
                            root.resizeHandle = ""
                            root.resizeCommitRequested()
                            if (dx !== 0 || dy !== 0)
                                root.resizeOriginShift(dx, dy)
                        }
                    }

                    onTranslationChanged: {
                        const r = Resize.planResize({
                            handle: handleItem.h,
                            start: { w: startW, h: startH },
                            dx: translation.x,
                            dy: translation.y,
                            minW: root.baseKbWidth * 0.8,
                            minH: root.baseKbHeight * 0.8,
                            maxW: root.screenW,
                            // 最高只到屏幕 2/3，再高就把应用内容压没了
                            maxH: Math.round(root.screenH * 2 / 3),
                            // 只有**停靠**模式拖左右时是对称的（键盘水平居中、
                            // 两边一起收才不跑位）。浮动模式下四个方向都是单边的：
                            // 拖哪边就只动哪边，宽高互不影响。
                            symmetric: !root.isFloating
                                && (handleItem.h === "e" || handleItem.h === "w"),
                            // 角落始终按当前宽高比缩放
                            aspect: startW / Math.max(1, startH),
                        })
                        root.resizeW = r.w
                        root.resizeH = r.h
                    }
                }
            }
        }

        // 调整大小面板的中心按钮组：圆形底 + 图标。
        // 必须在 Repeater 之外（Repeater 只渲染 delegate，
        // 放在里面的其它子项会被静默丢掉 —— 踩过一次）
        Row {
            anchors.centerIn: parent
            spacing: root.gap * 2
            z: 10

            readonly property real btn: Math.round(root.keyH * 0.92)

            // 铺满 / 不铺满（停靠态专用，浮窗没有这个概念）
            Rectangle {
                visible: !root.isFloating
                width: parent.btn
                height: parent.btn
                radius: width / 2
                color: root.dockFill ? Theme.primary : Theme.surfaceContainerHigh
                DankIcon {
                    anchors.centerIn: parent
                    name: root.dockFill ? "collapse_content" : "expand_content"
                    size: Math.round(root.keyH * 0.42)
                    color: root.dockFill ? Theme.onPrimary : Theme.withAlpha(root.fg, 0.85)
                }
                Ripple {
                    id: fillRipple
                    anchors.fill: parent
                    cornerRadius: width / 2
                    rippleColor: root.dockFill ? Theme.onPrimary : Theme.primary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => fillRipple.press(mouse.x, mouse.y)
                    onReleased: fillRipple.release()
                    onCanceled: fillRipple.release()
                    onClicked: root.resizeFillToggleRequested()
                }
            }

            // 重置回名义尺寸
            Rectangle {
                width: parent.btn
                height: parent.btn
                radius: width / 2
                color: Theme.surfaceContainerHigh
                DankIcon {
                    anchors.centerIn: parent
                    name: "restart_alt"
                    size: Math.round(root.keyH * 0.42)
                    color: Theme.withAlpha(root.fg, 0.85)
                }
                Ripple {
                    id: resetRipple
                    anchors.fill: parent
                    cornerRadius: width / 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => resetRipple.press(mouse.x, mouse.y)
                    onReleased: resetRipple.release()
                    onCanceled: resetRipple.release()
                    onClicked: root.resizeResetRequested()
                }
            }

            // 取消：还原进入时的尺寸
            Rectangle {
                width: parent.btn
                height: parent.btn
                radius: width / 2
                color: Theme.surfaceContainerHigh
                DankIcon {
                    anchors.centerIn: parent
                    name: "close"
                    size: Math.round(root.keyH * 0.42)
                    color: Theme.withAlpha(root.fg, 0.85)
                }
                Ripple {
                    id: cancelRipple
                    anchors.fill: parent
                    cornerRadius: width / 2
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => cancelRipple.press(mouse.x, mouse.y)
                    onReleased: cancelRipple.release()
                    onCanceled: cancelRipple.release()
                    onClicked: root.resizeCancelRequested()
                }
            }

            // 确定：关面板（尺寸松手时已经落盘）
            Rectangle {
                width: parent.btn
                height: parent.btn
                radius: width / 2
                color: Theme.primary
                DankIcon {
                    anchors.centerIn: parent
                    name: "check"
                    size: Math.round(root.keyH * 0.42)
                    color: Theme.onPrimary
                }
                Ripple {
                    id: okRipple
                    anchors.fill: parent
                    cornerRadius: width / 2
                    rippleColor: Theme.onPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => okRipple.press(mouse.x, mouse.y)
                    onReleased: okRipple.release()
                    onCanceled: okRipple.release()
                    onClicked: root.resizeCloseRequested()
                }
            }
        }
    }
}