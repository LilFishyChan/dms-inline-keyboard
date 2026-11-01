// Inline Keyboard 的键盘卡片本体：顶部快捷栏 + 右上角动作槽、按键区（page1/page2）、表情页、透明度面板和功能列表。

import "motion.js" as Motion
import "alpha.js" as Alpha
import QtQuick
import Quickshell.Io
import "actions.js" as Actions
import "data.js" as Data
import "layouts/phone.js" as Layout
import "layouts/resize.js" as Resize
import "modifiers.js" as Modifiers
import qs.Common
import qs.DCommon.Widgets

// 键盘主体：顶部快捷条 + 候选/快捷栏 + 键区（或功能列表） + 底部把手条
Rectangle {
    // ── 拖动公共入口 ────────────────────────────────────────────────
    // 避免每个 delegate 各写一份几乎相同的 onActiveChanged。
    // ── 落点动作（由 endDrag 分发）────────────────────────────────
    id: root

    // 打开时淡入：只动 opacity，不动几何（layer-shell 改尺寸会抖）
    readonly property bool hostVisible: root.Window.window ? root.Window.window.visible : true
    // 尺寸（由窗口按屏幕宽度/用户设置算好后传进来）
    property real unit: 63
    property real keyH: 64
    property real gap: 6
    property real pad: 8
    property real candH: 44
    // 写死像素值的缩放系数（窗口传 metrics.uiScale，840 宽时为 1）
    property real designScale: 1
    // 表情页分段按钮的当前索引，供诊断 IPC 断言（emojiPanel 的 id 只在组件内部可见）
    readonly property int emojiSegmentIndex: emojiPanel ? emojiPanel.segmentIndex : -1
    // 底部把手高度，比例和 KeyboardMetrics.handleRatio 一致；
    // 窗口总会传 metrics.handleH，这里只是兜底
    property real handleH: Math.round(root.keyH * 0.75)
    property bool showHandle: true
    property bool dragEnabled: false
    // 长按自动重复的间隔（毫秒），由设置页配置
    property int repeatInterval: 60
    // 候选栏整行的开关：显示条件看**这个输入法在 fcitx5 下会不会弹候选窗**，必须写成一行：QML 的 JS 在换行处会插分号，多行表达式会被截断成半句。
    property bool showCandBar: false
    property bool fnActive: false
    // Esc 与 ` 对调（设置项）
    property bool escSwap: false
    // 修饰键状态快照（0 未激活 / 1 一次性 / 2 锁定）
    property var modifierStates: ({
    })
    property string page: "page1"
    // 表情页的两级选择：段（表情 / 符号）+ 分类（"all" 或分组 id）。
    // 放在卡片上是因为顶部分类条和中间的网格要读同一份状态。
    property string emojiSegment: "emoji"
    property string emojiCategory: "all"
    // 最近一次选词：元素是「传进 addon 的 index」和「此刻该下标对应的词」。
    property string lastSelectInfo: ""
    // 有候选才显示候选行；没有候选时退回快捷键行
    // keys = 正常键盘；functions = 快捷功能列表
    property string mode: "keys"
    // 动作列表的编辑态（拖动排序）
    property bool editing: false
    // 停靠模式下是否避让键盘：对应动作的"激活"状态
    property bool avoidWindows: true
    // 当前是否浮动窗口（浮窗下"避让窗口"没有意义 → 禁用态）
    property bool isFloating: false
    // 透明度：由插件设置决定（0.1 ~ 1.0），不跟 DMS 主题走
    property real bgOpacity: 1
    property real keyOpacity: 1
    // 进入调整面板前的值，"取消"时恢复
    property real prevBgOpacity: 1
    property real prevKeyOpacity: 1
    // 右上角圆形动作槽的内容（可被列表里的动作拖进来替换）
    property string slotActionId: "float"
    property var quickBarActions: []
    // 槽里的动作从列表里按 id 找，找不到就用默认的语音输入
    readonly property var rightSlot: {
        if (!slotActionId)
            return null;

        const list = actionList || [];
        for (let i = 0; i < list.length; i++) {
            if (list[i].id === slotActionId)
                return list[i];

        }
        // id 指向的动作不在表里了，也算空
        return null;
    }
    property bool dragOverSlot: false
    // 固定栏落点：-1 = 没落在固定栏上；>= 0 = 插入位置（0..固定栏动作数）
    property int dragBarIndex: -1
    readonly property bool dragOverBar: root.dragBarIndex >= 0
    // 拖动来源："" 列表 / "bar" 快捷栏 / "slot" 右上角槽
    property string dragFrom: ""
    property int dragFromIndex: -1
    // 跟手的拖动块（圆形+图标），坐标是卡片坐标系（不是场景坐标）
    property real ghostX: 0
    property real ghostY: 0
    property var ghostAction: null
    // 语音输入是否在录音（daemon 传下来，决定顶部是否切到语音行）
    property bool tooltips: true
    property bool voiceActive: false
    // 语音模式：只留顶部语音行。由 daemon 传下来（daemon 负责切浮动），卡片只负责按它隐藏主区和底栏。
    property bool voiceMinimal: false
    // vinput 是否可用：没装时语音动作禁用，键盘其它功能不变
    property bool voiceAvailable: false
    // 拖动是否进行中（DragHandler.active 的镜像，用来兜底清理）
    property bool dragActive: false
    // 拖动锁：多点触控时只认第一个开始拖的，避免新触点把状态覆盖
    property string dragOwner: ""
    // 让位动画开关。默认 false：卡片构造期间功能栏的 x/width 会从默认值
    property bool animateCells: false
    // 本地 animateCells 只管首帧，DMS 关掉动画时这里也要停
    readonly property bool animationsEnabled: !SettingsData.reduceMotion && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None
    // 松手后幽灵块淡出，动画结束再真正移除
    property bool ghostFading: false
    // 按下点在"卡片"坐标系里的位置（按下时算一次，之后只加位移）
    property real pressCardX: 0
    property real pressCardY: 0
    property int dragIndex: -1
    property int dragTarget: -1
    // 跟手块在滚动容器里的坐标。拖动中每帧都变，算一次缓存住；
    // 落点计算、自动滚动、松手判定都用它。
    readonly property var ghostInListView: {
        const view = root.actionListRef;
        if (!view || !root.dragActive)
            return null;

        return view.mapFromItem(root, root.ghostX, root.ghostY);
    }
    readonly property bool ghostOverList: {
        const pos = root.ghostInListView;
        const view = root.actionListRef;
        if (!pos || !view)
            return false;

        return pos.x >= 0 && pos.x <= view.width && pos.y >= 0 && pos.y <= view.height;
    }
    // 顶部快捷条的按钮（目前两个，后面可扩展）
    readonly property var quickBarItems: [{
        "icon": "apps",
        "action": "nav",
        "kind": "nav"
    }, {
        "icon": "mic",
        "action": "mic",
        "kind": "slot"
    }]
    property bool imPickerOpen: false
    property var imList: []
    // 给输入法面板用：带 text / current 的加工后列表（imList 是 fcitx 原始列表）
    property var imRows: []

    // 长按选择器点了一行：分派规则和地球键单击一致（纯键盘布局直接切，拼音类要校正中英文）
    // 语音行里的垃圾桶：主键盘里 controller 是这张卡片，daemon 那边的实现在窗口转发之后
    function discardVoiceRecording() {
        root.discardVoiceRequested();
    }

    function selectIm(name) {
        root.imSelected(name, null);
    }

    function selectImMode(name, wantAscii) {
        root.imSelected(name, wantAscii);
    }
    readonly property var rows: {
        const base = Layout.pageRows(page);
        return root.escSwap ? root.swapEscTilde(base) : base;
    }
    // 当前页摊平后的键位列表：spaceEntry 与 Repeater 共用一份，避免每次算两遍
    // 走 root.rows：escSwap 在那一层做的替换必须传下去，否则键位还是原始布局
    readonly property var flatKeys: Layout.layoutFlat(page, root.rows)
    // 候选 / 快捷条：候选来自 fcitx5 addon（inline-keyboard-status.json），没有候选时显示快捷键
    readonly property var candidates: root.fcitxCandidates
    readonly property string preedit: root.fcitxPreedit
    readonly property color fg: Theme.surfaceText
    // 顶部快捷条高度 = 圆形按钮直径（按钮填满这一行）。
    // 窗口总会传 metrics.quickH，这里的默认值只是没接线时的兜底，比例要和 KeyboardMetrics.quickBarRatio 保持一致。
    property real quickH: Math.round(keyH * 0.78)
    // 动作表由插件设置提供（daemon 传进来）
    property var actionList: []
    // fcitx5 候选（daemon 从 inline-keyboard-status.json 读入）
    property var fcitxCandidates: []
    // 调试注入的假候选（dms ipc call inlineKeyboard debugCand "一,二,三"）。
    property var debugCandItems: []
    // 候选列表页是否展开。展开时键区让位（真换页，不是盖一层），否则下面的按键还会被点到。
    property bool candListOpen: false
    // 候选面板引用（调试用）
    property var candListPanel: null
    // 候选内容变化计数（FcitxBridge.candRevision 传下来）
    property int candRevision: 0
    // 全量候选（窗口从 FcitxBridge 转发下来）
    property var allCandidates: []
    // 正在等 addon 回包
    property bool candLoading: false
    // 「刚选过词」窗口：选词是明确动作，列表页此时也不会再打字，所以这段时间里候选变化要立刻处理，不能走 800ms 的打字 debounce。
    property bool recentSelect: false
    // 主键区行数，候选列表页的滚动区高度按它算
    readonly property int keyRowCount: Layout.pageRows("page1").length
    // 特殊键的表现形式（见 layouts/specialKeys.js）
    property string specialKeyStyle: "full"
    property string winKeyStyle: "mod"
    property string winKeyCustomIcon: ""
    // 调整大小面板：预览尺寸 / 名义尺寸 / 屏幕尺寸 / 停靠是否铺满
    property real resizeW: 1050
    // 正在拖的把手（"n"/"s"/"e"/"w"…，空串=没在拖）。
    // 预览框靠它决定钉住哪条边，拖动时只往一侧扩。
    property string resizeHandle: ""
    property real resizeH: 444
    property real baseKbWidth: 1050
    property real baseKbHeight: 444
    property real screenW: 1920
    property real screenH: 1080
    property bool dockFill: true
    // 候选列表页的数据源：真实全量候选优先；调试注入的 {i,t} 兜底
    property var debugCandModel: []
    // addon 推的顶部候选也是纯字符串数组，同样要缓存成 {i,t}，否则 candListModel 每次求值都要 map 一遍（18 个对象/次）。
    property var fcitxModel: []
    // 候选**列表页**的数据源：全量优先。
    // 不能拿来喂候选栏：allCandidates 是懒加载的，只有展开列表时才拉取。
    readonly property var candListModel: {
        if (root.allCandidates.length > 0)
            return root.allCandidates;

        if (root.debugCandModel.length > 0)
            return root.debugCandModel;

        return root.fcitxModel;
    }
    // 候选**栏**的数据源：永远用 items（addon 每 40ms 推的实时顶部候选）。
    // 调试注入时用调试数据。
    readonly property var candBarSource: {
        if (root.debugCandModel.length > 0)
            return root.debugCandModel;

        return root.fcitxModel;
    }
    // 候选栏能装下 candListModel 的前几项。
    // 剩下的进列表页，两边不重复。所以容量必须按同一份数据算，否则会同时显示或同时漏掉一个。
    property int candBarCount: 0
    // 顶栏词区的可用宽度：卡片宽减去两侧内边距，再减右侧展开按钮那一列（按钮直径 + 间距）
    readonly property real candBarAvail: Math.max(0, root.width - root.pad * 2 - (root.quickH + root.gap))
    // 单个候选词左右的内边距，按候选栏高度算（和 CandidateBar 共用同一个值，否则量容量和画出来的宽度对不上）
    readonly property real candItemPad: Math.round(root.candH * 0.8)
    // 候选栏显示前一段
    property var candBarItems: []
    // 顶栏排完后剩下的宽度，按项数分摊给每一项（列表也是这么铺满行尾的）
    property real candBarSlack: 0
    property var candListItems: []
    readonly property var candBarSlice: candBarItems
    // 候选列表页显示后一段（不含顶栏已有的，避免重复）。
    // 候选数据的版本号：candListModel 的任何来源变了都 ++。
    // 不能只靠 candRevision：那是 FcitxBridge 的推送计数，调试注入不会动它。
    property int candDataSeq: 0
    // 预编辑字符串一消失，列表页就自动收起。
    // 调试注入不算结束，否则 debugCand 模式下 fcitxPreedit 恒空、一展开就被收起。
    readonly property bool candsFinished: candListOpen && fcitxPreedit === "" && debugCandItems.length === 0
    // 候选列表页拿全量后段。渲染量由 CandidatePanel 自己虚拟化控制
    // （只实例化可视行），所以这里不需要再切窗口。
    readonly property var candListSlice: root.candListItems
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
    // 第三个参数必须用「冻结后」的固定栏：松手后到数据回来之前，固定栏已经显示新顺序了，用旧列表算会和眼睛看到的不一致。
    readonly property var availableActions: Actions.visibleActions(root.frozenList || actionList, slotActionId, root.frozenBar || quickBarActions)
    // 动作当前状态：active（开着的开关）/ disabled（当前不可用）/ default。
    // 必须是**属性绑定**而不是函数：函数体里读的 avoidWindows/isFloating 不会被
    readonly property var actionStates: ({
        "float": root.isFloating ? "active" : "default",
        "avoid": root.isFloating ? "disabled" : (root.avoidWindows ? "active" : "default"),
        "mic": root.voiceAvailable ? "default" : "disabled"
    })
    // 拖动预览：编辑态显示「松手后会变成的样子」
    // 固定栏最多放几个：按可用宽度算，另设 6 个的软上限免得挤成一排
    readonly property int quickBarCapacity: quickBar ? Math.max(1, Math.min(6, Math.floor((quickBar.midW + gap) / (quickBar.slotW + gap)))) : 4
    // 落在固定栏时的最终结果（预览和落盘共用 actions.js 的 planQuickBarDrop）
    readonly property var barDropPlan: {
        if (!(root.editing && root.dragActive && root.ghostAction))
            return null;

        // 拖到槽（交换）：原槽动作插到被抓项腾出的那一格。走同一套 plan，固定栏布局才是「源项已移除 + X 已插入」的最终样子，其他块才会让位。
        if (root.dragOverSlot && root.dragFrom === "bar" && root.rightSlot)
            return Actions.planQuickBarDrop(root.quickBarDropArgs(root.rightSlot, root.dragFromIndex, root.dragFrom, root.dragFromIndex));

        if (root.dragBarIndex < 0)
            return null;

        return Actions.planQuickBarDrop(root.quickBarDropArgs(root.ghostAction, root.dragBarIndex, root.dragFrom, root.dragFromIndex));
    }
    // 松手后短暂保留落盘后的顺序：真实数据要等一个 IPC 往返才回到卡片，中间若用旧数组，位置会先跳回去、再动画到新位置（看起来就是"松手后又演了一遍"）
    property var frozenBar: null
    property var frozenList: null
    // 松手后固定栏的样子。注意：这里只用来**算位置**，绝不能拿它当 Repeater 的 model
    readonly property var quickBarResolved: Actions.quickBarViewActions({
        "bar": root.quickBarActions,
        "plan": root.barDropPlan,
        "frozen": root.frozenBar,
        "dragActive": root.dragActive,
        "dragFrom": root.dragFrom,
        "dragFromIndex": root.dragFromIndex
    })
    // 拖到固定栏时被挤出来的那个动作（列表里用幽灵块表示，不塞进 model）
    readonly property var listEjected: root.barDropPlan ? root.barDropPlan.ejected : null
    // 功能列表的列数（列表布局与落点计算共用）。
    readonly property real actionMinCellW: Math.round(240 * root.designScale)
    readonly property int actionListColumns: Math.max(2, Math.floor((root.width - root.pad * 2 + root.gap) / (root.actionMinCellW + root.gap)))
    // 列表视图引用：动作列表拆成 ActionList 组件后，拖动落点计算仍需要它
    property var actionListRef: null
    // 空格键的位置（只有 page1 有），用来把输入法图标叠在空格正中间
    readonly property var spaceEntry: {
        if (page !== "page1")
            return null;

        const list = root.flatKeys;
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (e.key && e.key.k === "space")
                return e;

        }
        return null;
    }
    readonly property real spaceX: spaceEntry ? spaceEntry.col * (unit + gap) : 0
    readonly property real spaceY: spaceEntry ? spaceEntry.row * (keyH + gap) : 0
    readonly property real spaceW: spaceEntry ? spaceEntry.key.w * unit + (spaceEntry.key.w - 1) * gap : 0
    // I18n.trFor 的上下文 id（= plugin.json 的 id），缺词条时回退英文原串
    readonly property string pluginId: "inlineKeyboard"
    // 卡片高度**固定**：一律按主键区的行数算。
    // 不能用 rows.length —— 那是「当前页」的行数，切到表情页（0 行）、功能列表页都会算错高度。
    readonly property int layoutRowCount: Layout.pageRows("page1").length

    signal quickBarChanged(var list)
    // 透明度面板改值只落在卡片上（绑定被打断），要往上抛给 daemon 才能保存
    signal opacityAdjusted(real bg, real key)
    // fcitx5 当前输入法
    signal imSwitchRequested()
    signal imCycleRequested()
    // ascii 为 null 表示纯键盘布局（没有中英文子模式），直接切输入法
    signal imSelected(string name, var ascii)
    signal resizeCommitRequested()
    // 松手落盘时用：键盘尺寸变成新值后，卡片位置要补偿多少，才能让「拖的那条边」的对侧保持不动。拖动过程中不移动键盘。
    signal resizeOriginShift(real dx, real dy)
    signal resizeCloseRequested()
    signal resizeCancelRequested()
    signal resizeResetRequested()
    signal resizeFillToggleRequested()
    // 换模式的请求：不能在子组件里直接写 card.mode —— 那是 daemon 的
    signal modeChangeRequested(string mode)
    signal allCandidatesRequested()
    signal keyPressed(var keyData)
    // 表情 / 符号上屏：卡片只负责报「点了哪个字符」，真正怎么提交（addon commit / 剪贴板）由 daemon 决定。
    signal textCommitRequested(string text)
    // 点了第 index 个候选
    signal selectCandidateRequested(int index)
    // 修饰键的按下/松开（只有「按住才生效」模式用，daemon 里会过滤非修饰键）
    signal modifierPressed(var keyData)
    signal modifierReleased(var keyData)
    signal quickAction(string action)
    signal voiceMinimalRequested()
    signal discardVoiceRequested()
    // 语音行里两个按钮的点击请求：卡片自己不处理，转发给窗口 → daemon。
    signal voiceMicRequested()
    // 浮动模式拖把手用：开始拖 / 拖了多少（像素）
    signal dragStarted()
    // 动作顺序变了 / 槽里的动作变了（交由 daemon 持久化）
    signal orderChanged(var orderedActions)
    signal slotChanged(string actionId)
    signal dragMoved(real dx, real dy)

    function pointerTapEmojiSegment(index) {
        return emojiPanel ? emojiPanel.pointerTapSegment(index) : false;
    }

    // 切页：交给按键路由，page 状态由 daemon 统一管。
    function goPage(target) {
        root.keyPressed({
            "k": "page",
            "to": target
        });
    }

    function selectCandidate(index) {
        const item = root.candListModel[index];
        root.lastSelectInfo = "idx=" + index + " word=" + (item && item.t !== undefined ? item.t : "?") + " at=" + Date.now();
        root.selectCandidateRequested(index);
        // 选词后立刻重拉全量并立刻重排，两条 debounce/throttle 都绕过。
        if (root.candListOpen) {
            root.recentSelect = true;
            selectWindowTimer.restart();
            candReloadTimer.stop();
            root.candLoading = true;
            root.allCandidatesRequested();
            candLoadGuard.restart();
            // 先把当前状态立刻刷上去；addon 回包后 candDataSeq 会再 ++ 一次，那次走的就是下面的 recentSelect 分支，同样是立即的
            if (candListPanel)
                candListPanel.forceRelayout();

        }
    }

    // 左键点击 → 交给 daemon 切模式
    function toggleVoiceMinimal() {
        root.voiceMinimalRequested();
    }

    function beginDrag(source, index, centroidPos, item, action) {
        if (root.dragOwner !== "")
            return false;

        if (!item) {
            console.error("[inline-keyboard] beginDrag 缺少 dragItem，忽略本次拖动");
            return false;
        }
        root.dragOwner = source + ":" + index;
        root.dragActive = true;
        root.dragFrom = source === "cell" ? "" : source;
        root.dragFromIndex = source === "cell" ? -1 : index;
        root.dragIndex = source === "cell" ? index : -1;
        root.dragTarget = source === "cell" ? index : -1;
        // 先算坐标再设 ghostAction：ghostAction 一变 DragGhost 就 visible，所以坐标要在它变之前算好。
        const origin = item.mapToItem(root, centroidPos.x, centroidPos.y);
        root.pressCardX = origin.x;
        root.pressCardY = origin.y;
        root.ghostX = origin.x;
        root.ghostY = origin.y;
        root.ghostAction = action;
        if (root.actionListRef) {
            // 停掉还在跑的滚动惯性，否则它继续抢手势
            root.actionListRef.cancelFlick();
            root.actionListRef.interactive = false;
        }
        return true;
    }

    function updateDrag(translation) {
        root.ghostX = root.pressCardX + translation.x;
        root.ghostY = root.pressCardY + translation.y;
        root.updateTargetFromGhost();
        root.updateDropTargets();
    }

    // 松开：取快照 → 清状态 → 按落点分发。
    // 顺序不能反：落点写入会触发 Repeater 重建、销毁当前 delegate，后面的代码就拿不到 owner 了。
    function endDrag() {
        const owner = root.dragOwner;
        if (!owner) {
            // 手势已经断了（delegate 被重建、或 endDrag 被重复调用）：至少把状态清干净，别把幽灵块和 dragActive 留在界面上
            root.clearDragState();
            return ;
        }
        const drop = {
            "source": owner.split(":")[0],
            "action": root.ghostAction,
            "barTarget": root.dragBarIndex,
            "overSlot": root.dragOverSlot,
            "inList": root.ghostOverList,
            "fromIndex": root.dragIndex,
            "toIndex": root.dragTarget,
            "sourceIndex": root.dragFromIndex
        };
        root.clearDragState();
        if (drop.action)
            root.commitDrop(drop);

    }

    // 清空拖动相关的全部状态（快照取完之后才有意义）
    function clearDragState() {
        root.dragBarIndex = -1;
        root.dragOverSlot = false;
        root.dragIndex = -1;
        root.dragTarget = -1;
        root.dragOwner = "";
        root.dragFrom = "";
        root.dragFromIndex = -1;
        root.dragActive = false;
        if (root.actionListRef)
            root.actionListRef.interactive = true;

        root.scheduleDragFinish();
    }

    // 按落点分发：固定栏 → 槽 → 拖回列表 → 列表内排序
    function commitDrop(drop) {
        if (drop.barTarget >= 0) {
            root.applyQuickBarDrop(drop.action, drop.barTarget, drop.source, drop.sourceIndex);
            return ;
        }
        if (drop.overSlot) {
            // 交换：被抓项进槽，槽里原来的动作回到被抓项原来的位置。
            const slotAction = root.rightSlot;
            if (drop.source === "bar") {
                // 固定栏 ↔ 槽 真交换：槽里那个动作回到被拖项腾出的固定栏位置
                const bar = Actions.toArray(root.quickBarActions).slice();
                if (slotAction) {
                    const at = Math.min(drop.sourceIndex, bar.length - 1);
                    if (at >= 0)
                        bar[at] = slotAction;
                    else
                        bar.push(slotAction);
                } else if (drop.sourceIndex >= 0 && drop.sourceIndex < bar.length) {
                    bar.splice(drop.sourceIndex, 1);
                }
                root.freezeBarTo(bar);
                root.quickBarChanged(bar);
            }
            root.slotChanged(drop.action.id);
            if (drop.fromIndex >= 0 && slotAction) {
                // 列表源：原槽动作搬到被抓项腾出的那一格
                const visible = (root.availableActions || []).filter((a) => {
                    return a && a.id !== drop.action.id && a.id !== slotAction.id;
                });
                root.commitListOrder(Actions.insertAtVisibleIndex(root.actionList, slotAction, visible, drop.fromIndex));
            }
            return ;
        }
        if (drop.source === "bar") {
            if (!drop.inList)
                return ;

            root.removeFromQuickBar(drop.sourceIndex);
            root.commitListOrder(root.listWithActionAt(drop.action, drop.toIndex));
            return ;
        }
        if (drop.source === "slot") {
            if (!drop.inList)
                return ;

            root.slotChanged("");
            root.commitListOrder(root.listWithActionAt(drop.action, drop.toIndex));
            return ;
        }
        if (drop.inList && drop.fromIndex >= 0 && drop.toIndex >= 0 && drop.fromIndex !== drop.toIndex) {
            // 落位立即生效（frozenList 已把新顺序摆好），不需要再演一遍位移动画
            root.animateCells = false;
            root.moveAction(drop.fromIndex, drop.toIndex);
        }
    }

    // 列表顺序落盘：先按最终顺序冻结（松手瞬间就摆好，不演动画），再发出去。
    // 数据回来时顺序已经一样，不会再有第二段位移。
    function commitListOrder(list) {
        if (!list)
            return ;

        root.animateCells = false;
        root.frozenList = list;
        freezeListTimer.restart();
        root.orderChanged(list);
    }

    // 落到固定栏：与拖动预览共用同一份 plan，保证「看到什么就得到什么」
    function applyQuickBarDrop(action, index, source, sourceIndex) {
        const plan = Actions.planQuickBarDrop(root.quickBarDropArgs(action, index, source, sourceIndex));
        root.freezeBarTo(plan.bar);
        root.quickBarChanged(plan.bar);
        if (plan.slotActionId !== root.slotActionId)
            root.slotChanged(plan.slotActionId);

        root.commitListOrder(plan.actionList);
    }

    // 松手后先把固定栏的最终顺序冻结住，等真实数据追上来再解除 ——
    // 否则位置会先弹回拖动前的样子、数据回来后再动一次（看着像演了两遍）
    function freezeBarTo(bar) {
        root.frozenBar = bar;
        freezeBarTimer.restart();
    }

    // 从固定栏移除某一项（拖到槽 / 拖出到列表），顺带冻结结果
    // at 是可见列表下标，不能直接拿去 splice actionList（隐藏项也占名额）
    function listWithActionAt(action, at) {
        if (!action)
            return null;

        // 先排除动作自身：槽清空后它就在 availableActions 里
        const visible = (root.availableActions || []).filter((a) => {
            return a && a.id !== action.id;
        });
        return Actions.insertAtVisibleIndex(root.actionList, action, visible, at);
    }

    function removeFromQuickBar(index) {
        // 用 toArray：quickBarActions 可能是 QML 包过的类数组，直接 slice 会失效
        const bar = Actions.toArray(root.quickBarActions).slice();
        if (index < 0 || index >= bar.length)
            return ;

        bar.splice(index, 1);
        root.freezeBarTo(bar);
        root.quickBarChanged(bar);
    }

    // 按显示位置移动动作；真正的重排逻辑在 actions.js（有单测）
    function moveAction(fromDisplay, toDisplay) {
        const shown = root.availableActions || [];
        const fromAction = shown[fromDisplay];
        if (!fromAction)
            return ;

        // 拖到最后一项之后：追加到末尾（落点索引可以等于数组长度）
        if (toDisplay >= shown.length) {
            const moved = Actions.moveActionToEndById(root.actionList, fromAction.id);
            root.frozenList = moved;
            freezeListTimer.restart();
            root.orderChanged(moved);
            return ;
        }
        const toAction = shown[toDisplay];
        if (!toAction)
            return ;

        const moved = Actions.moveActionById(root.actionList, fromAction.id, toAction.id);
        // 冻结：松手后到数据回来之前，列表就按「移动后」的顺序摆，别先弹回去再动画一遍
        root.frozenList = moved;
        freezeListTimer.restart();
        root.orderChanged(moved);
    }

    // 拖动收尾（延后一帧执行，避免和 Repeater 重建撞车）
    // delegate 里拿不到根部 Timer 的 id，统一从这里转
    function scheduleDragFinish() {
        dragDeferTimer.restart();
    }

    function reenableAnim() {
        // 列表还在冻结中就先别开动画：数据回来时顺序万一差一点点，开了会看到松手后补一段位移
        if (root.frozenList)
            return ;

        root.animateCells = true;
    }

    // 判断逻辑在 data.js（有单测），这里只负责把当前动作表传进去
    function actionExists(id) {
        return Data.actionExists(root.actionList, id);
    }

    // 根据跟手块的位置算列表落点（快捷栏/槽拖回列表时用）
    function updateTargetFromGhost() {
        const view = root.actionListRef;
        const inScroll = root.ghostInListView;
        if (!root.ghostOverList || !view || !inScroll) {
            // ghost 在列表外（拖去固定栏 / 槽）：列表显示「移除后的样子」——
            root.dragTarget = -1;
            return ;
        }
        root.dragTarget = Actions.dropIndexAt(inScroll.x, inScroll.y + view.contentY, view.width, (root.availableActions || []).length, root.keyH, root.gap, actionListColumns);
    }

    // 计算落点：右上角槽 / 固定栏（三种拖动源共用）。
    // 固定栏不看「整块区域」，而是换算成插入位置 —— 拖动时才能显示松手后的样子。
    function updateDropTargets() {
        if (!quickBar) {
            root.dragOverSlot = false;
            root.dragBarIndex = -1;
            return ;
        }
        const barOrigin = quickBar.mapToItem(root, 0, 0);
        const slotLeft = barOrigin.x + quickBar.width - quickBar.btnW;
        const slotTop = barOrigin.y + (quickBar.height - quickBar.btnW) / 2;
        root.dragOverSlot = root.ghostX >= slotLeft && root.ghostX <= slotLeft + quickBar.btnW && root.ghostY >= slotTop && root.ghostY <= slotTop + quickBar.btnW;
        const midLeft = barOrigin.x + quickBar.midX;
        const inBand = !root.dragOverSlot && root.ghostY >= barOrigin.y && root.ghostY <= barOrigin.y + quickBar.height && root.ghostX >= midLeft && root.ghostX <= midLeft + quickBar.midW;
        // 插入索引必须按「眼睛看到的布局」算：slotGap 是按 previewCount 摊开的，不能按槽宽直接除。
        const previewCount = (root.quickBarResolved || []).length;
        // 要跳过的格 = 幽灵块**实际显示**的那一格，也就是上一帧 plan 的 insertedAt。
        // 不能传 dragBarIndex（那是原始数组里的下标，和预览布局差一位），要传幽灵块当前显示的那一格。
        const ghostCell = root.barDropPlan ? root.barDropPlan.insertedAt : -1;
        let rawIndex = inBand ? Actions.quickBarInsertIndex(root.ghostX - midLeft, previewCount, quickBar.slotW, quickBar.slotGap, ghostCell) : -1;
        let barIndex = rawIndex;
        // 预览索引 → 原始数组索引：源项还在原始数组里，planQuickBarDrop 内部
        // 摘掉源项时会把 index 减 1，这里先补回来
        if (barIndex >= 0 && root.dragFrom === "bar" && root.dragFromIndex >= 0 && barIndex >= root.dragFromIndex)
            barIndex += 1;

        root.dragBarIndex = barIndex;
    }

    // 拖动状态已由 clearDragState() 清过，这里只负责幽灵块的淡出
    function finishDrag() {
        root.ghostFading = true;
        ghostFadeTimer.restart();
    }

    function clearGhost() {
        root.ghostAction = null;
        root.ghostFading = false;
    }

    // 把 \`~ 键换成 Esc，Fn 层的 Esc 换成 \`~（角落键位习惯）
    // Esc ↔ ` 对调的逻辑在 data.js（有单测）
    function swapEscTilde(layoutRows) {
        return Data.swapEscTilde(layoutRows);
    }

    // 模拟使用流程：把一次点击 / 长按注入到某个键（不经过系统输入）
    function pointerTap(label, holdMs) {
        return keyArea ? keyArea.pointerTap(label, holdMs) : false;
    }

    function pointerTapAt(index, holdMs) {
        return keyArea ? keyArea.pointerTapAt(index, holdMs) : false;
    }

    function keySnapshot() {
        return keyArea ? keyArea.keySnapshot() : [];
    }

    // 模拟使用流程：其它控件的内部点击（走各自 MouseArea 抽出来的 tapAt）
    function pointerTapExpand() {
        return candBar ? candBar.pointerTapExpand() : false;
    }

    function pointerTapSide(act) {
        return candListPanel ? candListPanel.pointerTapSide(act) : false;
    }

    function pointerTapBottom(which) {
        return bottomBar ? bottomBar.pointerTap(which) : false;
    }

    function pointerTapAction(actionId) {
        return functionsArea ? functionsArea.pointerTapAction(actionId) : false;
    }

    function pointerTapNav() {
        return quickBar ? quickBar.pointerTapNav() : false;
    }

    function pointerTapBarAction(actionId) {
        return quickBar ? quickBar.pointerTapAction(actionId) : false;
    }

    function pointerTapSlot() {
        return quickBar ? quickBar.pointerTapSlot() : false;
    }

    function pointerTapEmojiCat(id) {
        return emojiCats ? emojiCats.pointerTapCategory(id) : false;
    }

    function recomputeCandBar() {
        const list = root.candBarSource;
        if (!list || list.length === 0 || root.candBarAvail <= 0) {
            root.candBarCount = 0;
            root.candBarSlack = 0;
            return ;
        }
        const avail = root.candBarAvail;
        // 首项最多占候选栏的三分之二，再长就省略前面（见 CandidateBar）
        const firstMax = avail * 2 / 3;
        let used = 0;
        let n = 0;
        for (let i = 0; i < list.length; i++) {
            const t = list[i] && list[i].t !== undefined ? String(list[i].t) : String(list[i] || "");
            candMeasure.text = t;
            let w = candMeasure.advanceWidth + root.candItemPad + root.gap;
            if (i === 0 && w > firstMax)
                w = firstMax;

            if (used + w > avail)
                break;

            used += w;
            n++;
        }
        root.candBarCount = n;
        root.candBarSlack = Math.max(0, avail - used);
        // 只有这里才切一次数组，下游读的是稳定引用
        root.candBarItems = n <= 0 ? [] : list.slice(0, n);
        // 列表页从候选栏之后开始，避免和顶栏重复。
        const waiting = root.candListOpen && root.candLoading && root.allCandidates.length === 0;
        root.candListItems = waiting ? [] : (n >= root.candListModel.length ? [] : root.candListModel.slice(n));
    }

    // 展开 / 收起候选列表页。打开时同时请求一次全量候选。
    // 全量候选要跨页生成，成本高，不能每次状态推送都拉。
    function toggleCandList() {
        root.candListOpen = !root.candListOpen;
        if (root.candListOpen) {
            root.candLoading = true;
            root.allCandidatesRequested();
            // addon 正常几十毫秒就回包；这里只是兜底，避免没装 addon 时
            // 面板永远停在「载入中」
            candLoadGuard.restart();
        } else {
            candLoadGuard.stop();
            root.candLoading = false;
        }
    }

    // 落到固定栏的入参：拖动预览和松手落盘必须是同一份，所以只在这里构造
    function quickBarDropArgs(action, index, source, sourceIndex) {
        return {
            "bar": root.quickBarActions,
            "actionList": root.actionList,
            "action": action,
            "index": index,
            "capacity": root.quickBarCapacity,
            "slotActionId": root.slotActionId,
            "source": source,
            "sourceIndex": sourceIndex
        };
    }

    // 内置动作名与表情分类名来自 actions.js / layouts/emoji.js，是运行时数据；
    // 提取工具只认字面量 trFor，所以在这里逐个列出来，找不到的（用户自定义动作名）原样返回
    function tr(term) {
        // 读一次翻译表建立依赖：表就绪后调用点的绑定会重算
        const table = (typeof I18n !== "undefined" && I18n) ? I18n.pluginTranslations : null;
        if (!table || !I18n.trFor)
            return term;

        switch (term) {
    case "Undo":
        return I18n.trFor("inlineKeyboard", "Undo");
    case "Redo":
        return I18n.trFor("inlineKeyboard", "Redo");
    case "Settings":
        return I18n.trFor("inlineKeyboard", "Settings");
    case "Float":
        return I18n.trFor("inlineKeyboard", "Float");
    case "Size":
        return I18n.trFor("inlineKeyboard", "Size");
    case "Opacity":
        return I18n.trFor("inlineKeyboard", "Opacity");
    case "Next input method":
        return I18n.trFor("inlineKeyboard", "Next input method");
    case "Clipboard":
        return I18n.trFor("inlineKeyboard", "Clipboard");
    case "Avoid windows":
        return I18n.trFor("inlineKeyboard", "Avoid windows");
    case "Voice input":
        return I18n.trFor("inlineKeyboard", "Voice input");
    case "Minimize":
        return I18n.trFor("inlineKeyboard", "Minimize");
    case "Smileys & Emotion":
        return I18n.trFor("inlineKeyboard", "Smileys & Emotion");
    case "People & Body":
        return I18n.trFor("inlineKeyboard", "People & Body");
    case "Animals & Nature":
        return I18n.trFor("inlineKeyboard", "Animals & Nature");
    case "Food & Drink":
        return I18n.trFor("inlineKeyboard", "Food & Drink");
    case "Travel & Places":
        return I18n.trFor("inlineKeyboard", "Travel & Places");
    case "Activities":
        return I18n.trFor("inlineKeyboard", "Activities");
    case "Objects":
        return I18n.trFor("inlineKeyboard", "Objects");
    case "Symbols":
        return I18n.trFor("inlineKeyboard", "Symbols");
    case "Flags":
        return I18n.trFor("inlineKeyboard", "Flags");
    case "Math":
        return I18n.trFor("inlineKeyboard", "Math");
    case "Punctuation":
        return I18n.trFor("inlineKeyboard", "Punctuation");
    case "Arrows":
        return I18n.trFor("inlineKeyboard", "Arrows");
    case "Currency":
        return I18n.trFor("inlineKeyboard", "Currency");
    case "Shapes":
        return I18n.trFor("inlineKeyboard", "Shapes");
    case "Box drawing":
        return I18n.trFor("inlineKeyboard", "Box drawing");
    case "Numbers":
        return I18n.trFor("inlineKeyboard", "Numbers");
    case "Misc":
        return I18n.trFor("inlineKeyboard", "Misc");
        default:
            return I18n.trFor("inlineKeyboard", term);
        }
    }

    // 索引换算在 data.js（有单测）；QuickBar 通过 controller 调这一层
    function quickBarIndexFor(id) {
        return Data.quickBarIndexFor(root.quickBarResolved, id);
    }

    // 键位 → 修饰键状态：映射规则在 modifiers.js（有单测），这里只查表
    function modifierStateFor(keyData) {
        const name = Modifiers.modifierNameFor(keyData);
        return name === "" ? 0 : (root.modifierStates[name] || 0);
    }

    opacity: hostVisible ? 1 : 0
    onCandRevisionChanged: {
        if (!root.candListOpen)
            return ;

        if (root.recentSelect) {
            // 选词刚发生：这是选词引起的候选变化，立刻处理
            candReloadTimer.stop();
            root.allCandidatesRequested();
            if (candListPanel)
                candListPanel.forceRelayout();

            return ;
        }
        // 普通打字：走 800ms，合并连续的按键
        candReloadTimer.restart();
    }
    onDebugCandItemsChanged: {
        debugCandModel = root.debugCandItems.map((t, n) => {
            return ({
                "i": n,
                "t": String(t)
            });
        });
        root.recomputeCandBar();
    }
    onFcitxCandidatesChanged: {
        fcitxModel = root.fcitxCandidates.map((t, n) => {
            return ({
                "i": n,
                "t": String(t)
            });
        });
        // 候选栏的数据源就是 fcitxModel，它一变就要重算容量 + 重排。
        root.recomputeCandBar();
        root.candDataSeq++;
    }
    onWidthChanged: recomputeCandBar()
    onUnitChanged: recomputeCandBar()
    onGapChanged: recomputeCandBar()
    // 高度变了 keyH 就变，候选测量的字号跟着变（candMeasure.font 依赖 keyH），容量必须重算 —— 否则拖高键盘后候选栏仍按旧字号排版，出现早省略
    onKeyHChanged: recomputeCandBar()
    Component.onCompleted: {
        recomputeCandBar();
        animSettleTimer.restart();
    }
    onCandListModelChanged: {
        // 顺序很重要：先重算切分，再发版本号。反过来的话面板收到
        root.recomputeCandBar();
        root.candDataSeq++;
    }
    // 全量候选回来就结束载入态，不必等到超时兜底。
    onAllCandidatesChanged: {
        if (root.allCandidates.length > 0)
            root.candLoading = false;

    }
    onCandsFinishedChanged: {
        if (candsFinished)
            autoCollapseTimer.restart();

    }
    width: unit * Layout.rowUnits + gap * (Layout.rowUnits - 1) + pad * 2
    // 和 Column 的结构逐项对齐，一项都不能少：这里也必须用同一个表达式，否则 Column 内容比卡片高、最后一项被挤出去。
    height: pad + Math.max(quickH, candH) + gap + layoutRowCount * keyH + Math.max(0, layoutRowCount - 1) * gap + handleH
    radius: Theme.windowRadius
    // 卡片底跟 DMS 设置页同色（hostSurface），透明度仍由插件设置控制
    color: Theme.withAlpha(Theme.hostSurface, bgOpacity)
    border.width: Theme.layerOutlineWidth
    border.color: Theme.outlineMedium

    // 选词窗口：600ms 后恢复正常（覆盖 addon 回包 + 一次状态推送）
    Timer {
        id: selectWindowTimer

        interval: 600
        repeat: false
        onTriggered: root.recentSelect = false
    }

    TextMetrics {
        id: candMeasure

        // 必须和 CandidateBar.candFontSize 一致，否则测出来的宽度和实际渲染不一样
        font.pixelSize: Math.round(root.keyH * 0.32)
        font.weight: Font.Normal
    }

    Timer {
        id: animSettleTimer

        interval: 150
        onTriggered: root.animateCells = true
    }

    Timer {
        id: autoCollapseTimer

        interval: 80
        repeat: false
        onTriggered: {
            if (!root.candsFinished)
                return ;

            root.candListOpen = false;
            root.recentSelect = false;
        }
    }

    // 展开状态下候选变了 → 重新拉全量。
    // 否则每打一个字就遍历一遍 BulkCandidateList（rime 懒加载，有成本）。
    Timer {
        id: candReloadTimer

        // 800ms：rime 的 BulkCandidateList 是懒加载，取一次要跨页生成，展开状态下每打几个字就重拉太贵，是主要的 CPU 抖动来源。
        interval: 800
        repeat: false
        onTriggered: {
            if (root.candListOpen) {
                root.candLoading = true;
                root.allCandidatesRequested();
                candLoadGuard.restart();
            }
        }
    }

    Timer {
        id: candLoadGuard

        interval: 1200
        repeat: false
        onTriggered: root.candLoading = false
    }

    // 透明度调整时，键盘外围画一圈提示边框
    Rectangle {
        anchors.fill: parent
        radius: Theme.windowRadius
        color: "transparent"
        border.width: Theme.outlineWidthFocused
        border.color: Theme.primary
        opacity: root.mode === "transparency" ? 1 : 0
        visible: opacity > 0.01
        z: 200

        Behavior on opacity {
            enabled: root.animateCells && root.animationsEnabled

            NumberAnimation {
                duration: Motion.dur(Motion.expand)
                easing.type: Easing.OutCubic
            }

        }

    }

    Column {
        anchors.fill: parent
        anchors.margins: root.pad
        // 底部不留 pad：把手行要贴到卡片底边
        anchors.bottomMargin: 0
        // 间距改由显式 spacer 控制 —— Column 的 spacing 对所有子项一律生效，没法只去掉「键区 ↔ 把手」那一段。
        spacing: 0

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
                // 用 opacity 而不是 visible：visible:false 期间内部几何不重算，切回主页面时槽会被摆到错误的键位上。
                opacity: (root.page === "emoji" || root.showCandBar || root.voiceActive) ? 0 : 1
                enabled: root.page !== "emoji" && !root.showCandBar && !root.voiceActive

                // 和分类栏 / 候选栏交叉淡入淡出，时长必须一致
                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            // 语音行：录音时占掉这一整行，优先级 语音 > 候选 > 功能
            VoiceBar {
                id: voiceRow

                controller: root
                anchors.fill: parent
                // 语音模式下即使暂停也要留在屏幕上 —— 否则麦克风一进未激活态
                // 整行就没了，用户看不到「点它可以继续」这个提示
                visible: opacity > 0
                opacity: (root.voiceActive || root.voiceMinimal) ? 1 : 0
                z: 20

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            // 候选栏：盖在快捷栏上面。
            CandidateBar {
                id: candBar

                controller: root
                anchors.fill: parent
                // 内层还在淡出时不能隐藏，否则过渡被砍断
                visible: (root.showCandBar || candBar.opacity > 0) && root.page !== "emoji" && !root.voiceActive
                z: 10
            }

            // 表情 / 符号页的分类条：占掉快捷栏那一行（快捷栏此处已淡出）
            EmojiCategoryBar {
                id: emojiCats

                controller: root
                anchors.fill: parent
                visible: opacity > 0
                opacity: root.page === "emoji" ? 1 : 0

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

        // 顶栏与键区之间的留白（把手行那边不加）
        Item {
            width: 1
            height: root.gap
        }

        // 两个子页共用同一块高度，靠 visible 切换，外层高度恒定
        Item {
            id: mainArea

            width: parent.width
            // 展开候选列表时整块键区让位：它是「换页」不是「盖一层」，按键必须真正隐藏，否则下面的按键还能被点到。
            height: root.layoutRowCount * root.keyH + Math.max(0, root.layoutRowCount - 1) * root.gap

            CandidatePanel {
                id: candListPanel

                Component.onCompleted: root.candListPanel = candListPanel
                // 度量（unit/keyH/gap/rowCount）和候选数据全从卡片拿，漏了这一行会导致 unit/gap 取默认兜底值，列表宽度算错
                controller: root
                anchors.fill: parent
                visible: root.candListOpen
                // 只做展开淡入：收起会立刻清空渲染量，淡出只剩空白
                opacity: root.candListOpen ? 1 : 0
                // 收起时把渲染量归零，避免隐藏状态下仍持有几百个 delegate
                shownCountOverride: root.candListOpen ? -1 : 0

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            // page1 ↔ page2 是同一个 Repeater 换 model，没有两层可以交叉淡入，所以切页时让键区整体从下方 6px 淡入一次，盖掉重建的突兀感。
            Item {
                id: keyWrapper

                property real pageFade: 1
                property real pageShift: 0

                anchors.fill: parent
                opacity: pageFade

                KeyGrid {
                    id: keyArea

                    // resize 时键区要留着（遮罩半透明），切面板走交叉淡入，visible 跟 opacity 走
                    readonly property bool shown: (root.mode === "keys" || root.mode === "resize") && root.page !== "emoji" && !root.candListOpen

                    controller: root
                    anchors.fill: parent
                    visible: opacity > 0.01
                    opacity: shown ? 1 : 0
                    enabled: shown && opacity > 0.5

                    Behavior on opacity {
                        enabled: root.animationsEnabled
                        NumberAnimation {
                            duration: Motion.dur(Motion.panel)
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                transform: Translate {
                    y: keyWrapper.pageShift
                }

            }

            // 切页动画：先瞬时归零（旧页直接消失），再从下方抬起淡入
            SequentialAnimation {
                id: pageSwap

                NumberAnimation {
                    target: keyWrapper
                    property: "pageFade"
                    to: 0
                    duration: 0
                }

                NumberAnimation {
                    target: keyWrapper
                    property: "pageShift"
                    to: 6
                    duration: 0
                }

                PauseAnimation {
                    duration: 16
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: keyWrapper
                        property: "pageFade"
                        to: 1
                        duration: Motion.dur(Motion.fade)
                        easing.type: Easing.OutCubic
                    }

                    NumberAnimation {
                        target: keyWrapper
                        property: "pageShift"
                        to: 0
                        duration: Motion.dur(Motion.fade)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            Connections {
                function onPageChanged() {
                    // 切到表情页走 EmojiPanel 自己的交叉淡入，这里不参与
                    if (root.page === "emoji")
                        return ;

                    // 关动画时直接落到终态，别让旧页停在半透明的中间态
                    if (!root.animationsEnabled) {
                        keyWrapper.pageFade = 1;
                        keyWrapper.pageShift = 0;
                        return ;
                    }
                    pageSwap.restart();
                }

                target: root
            }

            EmojiPanel {
                id: emojiPanel

                readonly property bool shown: root.mode === "keys" && root.page === "emoji" && !root.candListOpen

                controller: root
                anchors.fill: parent
                // 淡出要能一路走完，> 0.01 会让尾段直接跳没，子项（列表滚动条）跟着断
                visible: opacity > 0
                opacity: shown ? 1 : 0
                enabled: shown && opacity > 0.5

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            TransparencyPanel {
                id: transparencyArea

                readonly property bool shown: root.mode === "transparency"

                controller: root
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: shown ? 1 : 0
                enabled: shown && opacity > 0.5

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

            ActionList {
                id: functionsArea

                readonly property bool shown: root.mode === "functions"

                controller: root
                anchors.fill: parent
                visible: opacity > 0.01
                opacity: shown ? 1 : 0
                enabled: shown && opacity > 0.5

                Behavior on opacity {
                    enabled: root.animationsEnabled
                    NumberAnimation {
                        duration: Motion.dur(Motion.panel)
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

        // 放在 Column 末尾：它高度是 handleH、和卡片高度公式里的同一项，Column 各子项加起来正好等于 card height，不需要额外让位也不需要贴底。
        BottomBar {
            id: bottomBar

            controller: root
        }

    }

    // 拖动提交后的延迟收尾（Qt.callLater 会丢 root 上下文，用 Timer 代替）
    Timer {
        id: dragDeferTimer

        interval: 16
        onTriggered: {
            root.reenableAnim();
            root.finishDrag();
        }
    }

    // 冻结窗口：够一次 IPC 往返即可，太长会盖住别的变化
    // 固定栏冻结：松手后到真实数据回来之前先按落盘结果摆
    Timer {
        id: freezeBarTimer

        interval: 220
        onTriggered: root.frozenBar = null
    }

    // 列表冻结：和固定栏冻结互相独立，各自的定时器只清自己。
    Timer {
        id: freezeListTimer

        interval: 220
        onTriggered: {
            root.frozenList = null;
            root.animateCells = true;
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
                return ;

            root.dragIndex = -1;
            root.dragTarget = -1;
            root.ghostAction = null;
            root.dragOverSlot = false;
            if (root.actionListRef)
                root.actionListRef.interactive = true;

        }
    }

    // 放在卡片根部才不会被列表的 clip 裁掉
    DragGhost {
        id: dragGhost

        controller: root
    }

    ImPicker {
        id: imPicker

        controller: root
    }

    // 半透明遮罩压暗整个键盘（底下仍是键盘主页面），上面按当前尺寸画一个框，四角各一个拖拽手柄。
    Item {
        id: resizeArea

        // 把手的**命中区**厚度固定，不跟键盘尺寸走。
        readonly property real grip: Math.round(46 * root.designScale)
        // 停靠且铺满时宽度没得调 → 只剩顶边；否则按模式给对应把手
        readonly property var handles: {
            if (!root.isFloating && root.dockFill)
                return ["n"];

            // 已水平铺满，只能调高度
            return ["n", "e", "w"];
        }

        anchors.fill: parent
        visible: opacity > 0
        opacity: root.mode === "resize" ? 1 : 0
        // 盖在把手条（z 200）和所有页之上
        z: 300

        // 遮罩：整体键盘背景色的 50%
        Rectangle {
            anchors.fill: parent
            color: Theme.withAlpha(Theme.scrimColor, Theme.scrimAlpha)
            radius: Theme.windowRadius

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
            readonly property real outerW: (!root.isFloating && root.dockFill) ? resizeArea.width : Math.round(root.resizeW)
            // resizeH 是从窗口拖出来的名义高度，仍含底部 pad 和把手前的 gap；
            // 卡片实际比它矮这两项，预览框要跟着矮，否则框比卡片高出一截。
            readonly property real outerH: Math.round(root.resizeH) - root.pad - root.gap
            // 描边宽度：按键高取比例，比边框线粗一档才看得出是「可拖区域」
            readonly property real bw: Math.max(4, Math.round(root.keyH * 0.07))
            // 矩形按半个描边内缩：内层描边骑在自己的边界上，停靠模式：键盘本来就水平居中，拖左右必须**两边一起收/放**
            readonly property bool symmetricX: !root.isFloating && (root.resizeHandle === "" || root.resizeHandle === "e" || root.resizeHandle === "w")

            x: Math.round(symmetricX ? (resizeArea.width - outerW) / 2 : (root.resizeHandle.indexOf("w") >= 0 ? resizeArea.width - outerW : 0)) + bw / 2
            y: Math.round(root.resizeHandle.indexOf("n") >= 0 ? resizeArea.height - outerH : 0) + bw / 2
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
                readonly property real barLen: Math.min(200, Math.max(60, (horizontal ? fw : fh) * 0.3))

                // 命中区**完整落在框内**，不越过描边 —— 跨出去的部分在视觉上
                // 就是一条悬在框外的红线。居中用把手实际长度 barLen，不能用厚度 g。
                x: h === "w" ? fx : h === "e" ? fx + fw - g : fx + fw / 2 - barLen / 2
                y: h === "n" ? fy : h === "s" ? fy + fh - g : fy + fh / 2 - barLen / 2
                width: horizontal ? barLen : g
                height: vertical ? barLen : g

                Rectangle {
                    anchors.centerIn: parent
                    width: handleItem.horizontal ? parent.width : 6
                    height: handleItem.vertical ? parent.height : 6
                    radius: Theme.fullRadius(width, height)
                    color: Theme.primary
                }

                DragHandler {
                    // 高度上限是屏幕的 2/3，再高会把应用内容压没
                    property real startW: 0
                    property real startH: 0

                    target: null
                    cursorShape: handleItem.horizontal ? Qt.SizeVerCursor : Qt.SizeHorCursor
                    onActiveChanged: {
                        if (active) {
                            startW = root.resizeW;
                            startH = root.resizeH;
                            root.resizeHandle = handleItem.h;
                        } else {
                            // 松手即生效：把当前预览尺寸写进设置，键盘当场变成新大小。
                            const dx = handleItem.h.indexOf("w") >= 0 ? startW - root.resizeW : 0;
                            const dy = handleItem.h.indexOf("n") >= 0 ? startH - root.resizeH : 0;
                            root.resizeHandle = "";
                            root.resizeCommitRequested();
                            if (dx !== 0 || dy !== 0)
                                root.resizeOriginShift(dx, dy);

                        }
                    }
                    onTranslationChanged: {
                        const r = Resize.planResize({
                            "handle": handleItem.h,
                            "start": {
                                "w": startW,
                                "h": startH
                            },
                            "dx": translation.x,
                            "dy": translation.y,
                            "minW": root.baseKbWidth * Resize.MIN_FACTOR,
                            "minH": root.baseKbHeight * Resize.MIN_FACTOR,
                            "maxW": root.screenW,
                            "maxH": Math.round(root.screenH * 2 / 3),
                            "symmetric": !root.isFloating && (handleItem.h === "e" || handleItem.h === "w"),
                            "aspect": startW / Math.max(1, startH)
                        });
                        root.resizeW = r.w;
                        root.resizeH = r.h;
                    }
                }

            }

        }

        // 调整大小面板的中心按钮组：圆形底 + 图标。
        // 必须在 Repeater 之外（Repeater 只渲染 delegate，放进去会被复制成 N 份）。
        Row {
            readonly property real btn: Math.round(root.keyH * 0.92)

            anchors.centerIn: parent
            spacing: root.gap * 2
            z: 10

            // 铺满 / 不铺满（停靠态专用，浮窗没有这个概念）
            // 铺满 / 不铺满（停靠态专用，浮窗没有这个概念）
            DActionButton {
                visible: !root.isFloating
                buttonSize: parent.btn
                iconName: root.dockFill ? "collapse_content" : "expand_content"
                tooltipText: root.tooltips ? (root.dockFill ? I18n.trFor("inlineKeyboard", "Shrink to content") : I18n.trFor("inlineKeyboard", "Fill width")) : ""
                iconSize: Math.round(root.keyH * 0.42)
                iconColor: root.dockFill ? Theme.onPrimary : Theme.withAlpha(root.fg, Alpha.Bright)
                backgroundColor: root.dockFill ? Theme.primary : Theme.chipSurface
                stateColor: root.dockFill ? Theme.onPrimary : Theme.primary

                onClicked: root.resizeFillToggleRequested()
            }

            DActionButton {
                buttonSize: parent.btn
                iconName: "restart_alt"
                tooltipText: root.tooltips ? I18n.trFor("inlineKeyboard", "Reset size") : ""
                iconSize: Math.round(root.keyH * 0.42)
                iconColor: Theme.withAlpha(root.fg, Alpha.Bright)
                backgroundColor: Theme.chipSurface
                stateColor: Theme.withAlpha(root.fg, Alpha.Bright)

                onClicked: root.resizeResetRequested()
            }

            DActionButton {
                buttonSize: parent.btn
                iconName: "close"
                tooltipText: root.tooltips ? I18n.trFor("inlineKeyboard", "Cancel") : ""
                iconSize: Math.round(root.keyH * 0.42)
                iconColor: Theme.withAlpha(root.fg, Alpha.Bright)
                backgroundColor: Theme.chipSurface
                stateColor: Theme.withAlpha(root.fg, Alpha.Bright)

                onClicked: root.resizeCancelRequested()
            }

            DActionButton {
                buttonSize: parent.btn
                iconName: "check"
                tooltipText: root.tooltips ? I18n.trFor("inlineKeyboard", "Confirm") : ""
                iconSize: Math.round(root.keyH * 0.42)
                iconColor: Theme.onPrimary
                backgroundColor: Theme.primary
                stateColor: Theme.onPrimary

                onClicked: root.resizeCloseRequested()
            }

        }

        Behavior on opacity {
            enabled: root.animationsEnabled
            NumberAnimation {
                duration: Motion.dur(Motion.panel)
                easing.type: Easing.OutCubic
            }

        }

    }

    Behavior on opacity {
        enabled: root.animationsEnabled
        NumberAnimation {
            duration: Motion.dur(Motion.fade)
            easing.type: Easing.OutCubic
        }

    }

}
