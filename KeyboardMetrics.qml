// 键盘几何：把「窗口宽高 → 单元宽 / 键高 / 快捷条高 / 把手高」的推导集中到一处。
// 停靠窗口和浮动窗口共用这套公式，避免两条算式各自演化（改一处忘另一处）。
// 所有输入都是名义值：不能用 card.width / card.height 反算，否则会形成
// 「窗口尺寸 ← 卡片尺寸 ← 窗口尺寸」的正反馈，浮动窗口一拖就被压窄。
import QtQuick
import "layouts/phone.js" as Layout

QtObject {
    id: root

    // 顶部快捷条高度 / 底部把手高度，都按键高取比例
    readonly property real quickBarRatio: 0.78
    // 把手高度 = 键高的 0.75（原 0.5，加了一半）
    readonly property real handleRatio: 0.75
    readonly property int keyRowCount: Layout.pageRows("page1").length

    // ---- 输入（窗口绑定，或用户设置换算后的名义值）----
    property real kbWidth: 1050
    property real kbHeight: 444
    property real gap: 6
    property real pad: 8
    property real candH: 44
    property real screenH: 800

    property bool showCandBar: false
    property real screenW: 1280
    // 停靠模式铺满屏幕两侧；浮动模式保持名义宽度并留出边距，
    // 否则浮窗会被拉成整屏宽。
    property bool fillWidth: false
    readonly property real cardW: root.fillWidth
        ? root.screenW
        : Math.min(root.kbWidth, root.screenW - 24)
    // 一行 = rowUnits 个单元 + (rowUnits-1) 个间距 + 两侧内边距
    readonly property real unit:
        (cardW - pad * 2 - (Layout.rowUnits - 1) * gap) / Layout.rowUnits
    readonly property real quickH: Math.round(keyH * quickBarRatio)

    // 竖直方向：kbHeight = pad*2 + topArea(quickH 或 candH) + gap
    //                        + rows*keyH + (rows-1)*gap + handleRatio*keyH
    // 候选栏和快捷栏叠在同一个 topArea 里（二选一覆盖），不额外占高度，
    // 所以这里不能再减 candH——减了候选出现时 keyH 会缩小、整个键盘变矮。
    // 直接解出 keyH，避免「keyH 依赖 handleH、handleH 依赖 keyH」的循环绑定
    readonly property real keyH: Math.max(28,
        (kbHeight - pad * 2 - gap - (keyRowCount - 1) * gap)
        / (keyRowCount + quickBarRatio + handleRatio))
    readonly property real handleH: keyH * handleRatio
}
