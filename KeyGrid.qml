// 键位网格：绝对定位（同一行可能有跨行键，用 Grid/Row 反而要写一堆特例）。
// 空格键中间叠当前输入法标识，点击仍是空格键。
import QtQuick
import qs.Common
import qs.Widgets

Item {
    id: grid

    // 卡片实例：键位数据、尺寸、修饰键状态全从它读
    required property var controller

    readonly property var c: controller

    Repeater {
        id: keyRepeater
        model: grid.c.flatKeys

        delegate: Key {
            id: keyItem

            required property var modelData

            keyData: modelData.key
            unit: grid.c.unit
            keyH: grid.c.keyH
            gap: grid.c.gap
            span: modelData.rs
            fnActive: grid.c.fnActive
            // 字母大小写：shift 激活 / caps 锁定 → 大写
            upperMode: (grid.c.modifierStates.shift || 0) > 0
                       || (grid.c.modifierStates.caps || 0) > 0
            modifierState: grid.c.modifierStateFor(modelData.key)
            specialKeyStyle: grid.c.specialKeyStyle
            winKeyStyle: grid.c.winKeyStyle
            winKeyCustomIcon: grid.c.winKeyCustomIcon
            keyOpacity: grid.c.keyOpacity
            active: modelData.key.active === true
            x: modelData.col * (grid.c.unit + grid.c.gap)
            y: modelData.row * (grid.c.keyH + grid.c.gap)
            // 把按键的按下 / 松开 / 点击入口暴露给 grid：模拟点击走同一条代码路径
            property alias pointer: keyMouse

            MouseArea {
                id: keyMouse
                anchors.fill: parent
                enabled: !keyItem.isSpacer

                // 只有「按住能连续产出内容」的键才重复。
                // 判断必须按 label 白名单：k 是 "key" 的还有 Alt / Ctrl / Win /
                readonly property bool repeatable: {
                    const k = keyItem.keyData || {}
                    if (k.k === "char" || k.k === "space")
                        return true
                    if (k.k !== "key")
                        return false
                    const label = k.l || ""
                    return label === "Backspace" || label === "Del"
                        || label === "End" || label === "Home"
                        || label === "PgUp" || label === "PgDn"
                }

                // 按下 / 松开 / 点击各自成一个函数：手势直接调用，模拟点击也调它们，
                // 两条路共用同一份逻辑（长按重复、修饰键状态、涟漪都不会漏）
                function pressAt(px, py) {
                    keyItem.pressRipple(px, py)
                    grid.c.modifierPressed(keyItem.keyData)
                    // 可重复的键按下就出字，长按后由定时器接管
                    if (repeatable) {
                        grid.c.keyPressed(keyItem.effectiveKeyData)
                        holdTimer.restart()
                    }
                }

                function releaseAt() {
                    grid.c.modifierReleased(keyItem.keyData)
                    holdTimer.stop()
                    repeatTimer.stop()
                }

                function clickAt() {
                    if (!repeatable)
                        grid.c.keyPressed(keyItem.effectiveKeyData)
                }

                onPressed: mouse => pressAt(mouse.x, mouse.y)
                onReleased: releaseAt()
                onCanceled: releaseAt()
                onClicked: clickAt()

                // 长按判定：按住超过 400ms 开始重复
                Timer {
                    id: holdTimer
                    interval: 400
                    repeat: false
                    onTriggered: repeatTimer.start()
                }

                // 重复间隔由设置决定（ydotool 输出间隔）
                Timer {
                    id: repeatTimer
                    interval: Math.max(20, grid.c.repeatInterval || 60)
                    repeat: true
                    onTriggered: grid.c.keyPressed(keyItem.effectiveKeyData)
                }
            }
        }
    }

    // 空格键正中间：当前输入法标识（点击仍然是空格键）
    // 有文字标签（「万」/「en」/「abc」）就显示文字，和托盘一致；
    Image {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel === ""
                 && source !== ""
        // addon 直接给绝对路径（从 icon theme 解析），不需要缓存破除参数
        source: grid.c.fcitxImIcon === "" ? "" : "file://" + grid.c.fcitxImIcon
        width: Math.round(grid.c.keyH * 0.4)
        height: width
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + (grid.c.keyH - height) / 2
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    Text {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel !== ""
        text: grid.c.fcitxImLabel
        font.pixelSize: Math.max(10, Math.round(grid.c.keyH * 0.42))
        font.weight: Font.Medium
        color: Theme.onSurface
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + (grid.c.keyH - height) / 2
    }

    // ---- 模拟使用流程：把一次点击 / 长按注入到按键里 ----
    // 调的是上面同一组 pressAt / releaseAt / clickAt，所以长按重复、修饰键状态、
    // 页面切换、涟漪都会真实发生；不经过系统输入、不动鼠标。
    // holdMs 就是按住时长：超过 400ms 会触发长按重复（和手指一致）。

    property var pendingTap: null

    function keyItemFor(label) {
        if (!label)
            return null
        for (let i = 0; i < keyRepeater.count; i++) {
            const item = keyRepeater.itemAt(i)
            if (!item || !item.keyData || item.isSpacer || !item.pointer)
                continue
            const k = item.keyData
            const labels = [k.l]
            if (k.fn && k.fn.l)
                labels.push(k.fn.l)
            if (k.shift && k.shift.l)
                labels.push(k.shift.l)
            // 图标键（页键 / 表情 / 菜单）没有文字，用图标名当标签
            if (k.icon)
                labels.push(k.icon)
            if (labels.indexOf(label) >= 0)
                return item
        }
        return null
    }

    function keyItemAt(index) {
        if (index < 0 || index >= keyRepeater.count)
            return null
        const item = keyRepeater.itemAt(index)
        if (!item || item.isSpacer || !item.pointer)
            return null
        return item
    }

    // 调试：当前页所有非占位键（repeater 下标 + 当前显示标签 + 键码）。
    // 验收脚本用它按下标逐键点击，期望值另从布局数据算，不从渲染结果反推。
    function keySnapshot() {
        const out = [];
        for (let i = 0; i < keyRepeater.count; i++) {
            const item = keyRepeater.itemAt(i);
            if (!item || !item.keyData || item.isSpacer)
                continue;
            const k = item.keyData;
            // 标签和键码都取「当前生效层」：和 Key.qml 画出来的、真正注入的是同一份
            out.push({
                index: i,
                label: item.effectiveLabel === undefined ? "" : String(item.effectiveLabel),
                code: item.effectiveCode === undefined ? -1 : item.effectiveCode,
                kind: k.k === undefined ? "" : String(k.k),
                fnLabel: (k.fn && k.fn.l) ? String(k.fn.l) : "",
                hasShift: k.s !== undefined
            });
        }
        return out;
    }

    // 按下 → 等 holdMs → 松开并点击：pointerTap 按标签找，pointerTapAt 按格子下标找
    // （同名键、占位格里只有下标能唯一定位）
    // 收尾上一次没走完的点击：release 丢了 holdTimer 会一直挂着 → 长按重复失控。
    // 连发（脚本遍历）和定时器到点都走这一条路。
    function finishPendingTap() {
        const item = grid.pendingTap
        grid.pendingTap = null
        if (!item || !item.pointer)
            return
        item.pointer.releaseAt()
        item.pointer.clickAt()
    }

    function tapItem(item, holdMs) {
        if (!item)
            return false
        finishPendingTap()
        pendingTap = item
        item.pointer.pressAt(item.width / 2, item.height / 2)
        tapTimer.interval = Math.max(1, holdMs)
        tapTimer.restart()
        return true
    }

    function pointerTap(label, holdMs) {
        return tapItem(keyItemFor(label), holdMs)
    }

    function pointerTapAt(index, holdMs) {
        return tapItem(keyItemAt(index), holdMs)
    }

    Timer {
        id: tapTimer

        onTriggered: grid.finishPendingTap()
    }
}
