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

    // ---- 写死像素值的统一缩放 ----
    // 840 宽时 uiScale = 1，下面 base 值就是原值；键盘拖小/放大时等比跟着变。
    // 不缩放的话，candH 44 在 222 高的键盘上要占 20%（正常只有 10%），
    // gap 6×6 个间隙在 525 宽上也要吃掉 7%。
    readonly property real designW: 840
    readonly property real uiScale: Math.max(0.5, Math.min(1.6, root.cardW / root.designW))

    // ---- 输入（窗口绑定，或用户设置换算后的名义值）----
    property real kbWidth: 1050
    property real kbHeight: 444
    // 基准值（840 宽时生效），实际用的是下面三个 readonly 的缩放结果
    property real gapBase: 6
    property real padBase: 8
    property real candHBase: 44
    property real screenH: 800

    readonly property real gap: Math.round(root.gapBase * root.uiScale)
    readonly property real pad: Math.round(root.padBase * root.uiScale)
    readonly property real candH: Math.round(root.candHBase * root.uiScale)

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

    // cardHeight = pad + topH + gap + rows*keyH + (rows-1)*gap + handleH
    // topH = max(quickH, candH)，分两种情形解；直接解 keyH 避免与 handleH 循环依赖
    readonly property real cardHeight: kbHeight - pad - gap
    readonly property real verticalSlack:
        cardHeight - pad - gap - (keyRowCount - 1) * gap
    readonly property real keyH: {
        // 先假设顶栏由快捷栏决定（topH = keyH * quickBarRatio）
        const withQuick = verticalSlack / (keyRowCount + quickBarRatio + handleRatio)
        if (Math.round(withQuick * quickBarRatio) >= candH)
            return Math.max(28, withQuick)
        // 快捷栏排出来还没候选栏高 → 顶栏由 candH 撑开，重解
        return Math.max(28, (verticalSlack - candH) / (keyRowCount + handleRatio))
    }
    readonly property real handleH: keyH * handleRatio
}
