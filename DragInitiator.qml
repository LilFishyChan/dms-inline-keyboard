// 拖动起手：把 DragHandler 手势翻译成 controller 的 beginDrag / updateDrag / endDrag。
// 固定栏、槽、列表格三处共用；「按住才抓」靠 Flickable.pressDelay，不在这里。
import QtQuick

DragHandler {
    id: root

    property var controller: null
    // 拖动源标识："bar" 固定栏 / "slot" 右上角槽 / "cell" 列表格
    property string owner: ""
    property int ownerIndex: -1
    property var payload: null
    // 被拖的那个 delegate 本身。不能用 parent —— Handler 的 parent 是
    // 「声明它的 item 的父项」（固定栏那种是 QuickBar、列表是滚动容器），
    property var dragItem: null

    // 每次移动都会发一次；列表用它做「拖到可视区顶端/底端自动滚动」
    signal dragged(var translation)

    target: null
    // 滚动惯性还在跑时拖动会被 Flickable 抢走（「刚滚完拖一下没反应」）
    grabPermissions: PointerHandler.CanTakeOverFromAnything

// 用 pressPosition（按下那一刻）：快速拖动时 handler 激活已移了一段
    onActiveChanged: active
        ? root.controller.beginDrag(root.owner, root.ownerIndex, centroid.pressPosition,
                                    root.dragItem, root.payload)
        : root.controller.endDrag()

    onTranslationChanged: {
        if (!active)
            return
        // 没抢到拖动权（上一次残留 / 重复起手）就别动状态
        if (root.controller.dragOwner !== root.owner + ":" + root.ownerIndex)
            return
        root.controller.updateDrag(translation)
        root.dragged(translation)
    }
}
