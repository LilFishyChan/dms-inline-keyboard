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

    // 竖直方向（和 KeyboardCard 里 Column 的结构逐项对齐）：
    //   cardHeight = pad + topH + gap + rows*keyH + (rows-1)*gap + handleH
    // 底部把手行上下都不留白（贴键区、贴卡片底），所以只有**一段 gap**、
    // 而且底部不再有 pad —— 只剩顶部那一个 pad。
    //
    // kbHeight 是用户拖出来的旧尺寸，仍含原来的底部 pad 和把手前的 gap；
    // 这两项（pad + gap）现在是多余的高度，卡片比它矮这么多。
    // keyH 按 cardHeight 解，所以按键大小不受这次改动影响。
    //
    // topH = max(quickH, candH)：候选栏可能比快捷栏高，顶栏按两者较大的那个占位。
    // 于是要分两种情形解，否则卡片实际高度会比 kbHeight 多出一截，
    // 调整大小时的预览框就对不上卡片（踩过：444 名义、实际 450）。
    //
    // 直接解出 keyH，避免「keyH 依赖 handleH、handleH 依赖 keyH」的循环绑定。
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
