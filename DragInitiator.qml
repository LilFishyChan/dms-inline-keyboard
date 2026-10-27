// 拖动起手：把 DragHandler 的手势翻译成 controller 的 beginDrag / updateDrag / endDrag。
// 固定栏动作块、右上角槽、列表格这三处本来各写一份（其中两份逐字相同），统一到这里。
// 落点计算全在 controller 里，这里只负责「手势 → 调用」。
import QtQuick

DragHandler {
    id: root

    property var controller: null
    // 拖动源标识："bar" 固定栏 / "slot" 右上角槽 / "cell" 列表格
    property string owner: ""
    property int ownerIndex: -1
    property var payload: null

    // 每次移动都会发一次；列表用它做「拖到可视区顶端/底端自动滚动」
    signal dragged(var translation)

    target: null

    onActiveChanged: active
        ? root.controller.beginDrag(root.owner, root.ownerIndex, centroid.position, parent, root.payload)
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
