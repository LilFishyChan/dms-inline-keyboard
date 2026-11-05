// 键位网格：绝对定位（同一行可能有跨行键，用 Grid/Row 反而要写一堆特例）。
// 空格键中间叠当前输入法标识，点击仍是空格键。
import QtQuick
import "modifiers.js" as Modifiers
import qs.Common
import qs.Widgets

Item {
    // 模拟点击：走和手指同一组 pressAt / releaseAt / clickAt，不经过系统输入

    id: grid

    // 卡片实例：键位数据、尺寸、修饰键状态全从它读
    required property var controller
    readonly property var c: controller
    property var pendingTap: null

    function keyItemFor(label) {
        if (!label)
            return null;

        for (let i = 0; i < keyRepeater.count; i++) {
            const item = keyRepeater.itemAt(i);
            if (!item || !item.keyData || item.isSpacer || !item.pointer)
                continue;

            const k = item.keyData;
            const labels = [k.l];
            if (k.fn && k.fn.l)
                labels.push(k.fn.l);

            if (k.shift && k.shift.l)
                labels.push(k.shift.l);

            // 图标键（页键 / 表情 / 菜单）没有文字，用图标名当标签
            if (k.icon)
                labels.push(k.icon);

            if (labels.indexOf(label) >= 0)
                return item;

        }
        return null;
    }

    function keyItemAt(index) {
        if (index < 0 || index >= keyRepeater.count)
            return null;

        const item = keyRepeater.itemAt(index);
        if (!item || item.isSpacer || !item.pointer)
            return null;

        return item;
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
                "index": i,
                "label": item.effectiveLabel === undefined ? "" : String(item.effectiveLabel),
                "code": item.effectiveCode === undefined ? -1 : item.effectiveCode,
                "kind": k.k === undefined ? "" : String(k.k),
                "fnLabel": (k.fn && k.fn.l) ? String(k.fn.l) : "",
                "hasShift": k.s !== undefined
            });
        }
        return out;
    }

    // 收尾上一次没走完的点击：release 丢了 holdTimer 会一直挂着，长按重复会失控
    function finishPendingTap() {
        const item = grid.pendingTap;
        grid.pendingTap = null;
        if (!item || !item.pointer)
            return ;

        item.pointer.releaseAt();
        item.pointer.clickAt();
    }

    function tapItem(item, holdMs) {
        if (!item)
            return false;

        finishPendingTap();
        pendingTap = item;
        item.pointer.pressAt(item.width / 2, item.height / 2);
        tapTimer.interval = Math.max(1, holdMs);
        tapTimer.restart();
        return true;
    }

    function pointerTap(label, holdMs) {
        return tapItem(keyItemFor(label), holdMs);
    }

    function pointerTapAt(index, holdMs) {
        return tapItem(keyItemAt(index), holdMs);
    }

    Repeater {
        id: keyRepeater

        model: grid.c.flatKeys

        delegate: Key {
            id: keyItem

            required property var modelData
            // 把按键的按下 / 松开 / 点击入口暴露给 grid：模拟点击走同一条代码路径
            property alias pointer: keyMouse
            // 无障碍信息挂在 Key 上：TapHandler 不是 Item，拿不到 Accessible 附加属性
            Accessible.role: Accessible.Button
            Accessible.name: keyItem.bottomLabel || keyItem.iconName || keyItem.mainLabel
            Accessible.onPressAction: keyItem.pointer.activateAt()

            keyData: modelData.key
            unit: grid.c.unit
            keyH: grid.c.keyH
            gap: grid.c.gap
            borderWidth: grid.c.borderWidth
            span: modelData.rs
            fnActive: grid.c.fnActive
            // 字母大小写：shift 激活 / caps 锁定 → 大写
            // 字母大写：Caps 单独生效，Shift 反转 Caps（两个都开时回到小写，和标准键盘一致）
            upperMode: ((grid.c.modifierStates.shift || 0) > 0) !== ((grid.c.modifierStates.caps || 0) > 0)
            shiftActive: (grid.c.modifierStates.shift || 0) > 0
            modifierState: grid.c.modifierStateFor(modelData.key)
            specialKeyStyle: grid.c.specialKeyStyle
            winKeyStyle: grid.c.winKeyStyle
            winKeyCustomIcon: grid.c.winKeyCustomIcon
            keyOpacity: grid.c.keyOpacity
            active: modelData.key.active === true
            x: modelData.col * (grid.c.unit + grid.c.gap)
            y: modelData.row * (grid.c.keyH + grid.c.gap)

            // TapHandler 而不是 MouseArea：每个键一个实例、各自抓一个触摸点，
            // 两根手指按两个键会同时 pressed。MouseArea 不是 PointerHandler，
            // 触屏上 Qt 只合成一个鼠标指针，第二根手指的按键直接丢掉。
            TapHandler {
                id: keyMouse

                // 「没有多种状态」的键都重复：字符、空格，以及所有普通按键
                // （Tab / Enter / Esc / Backspace / Del / 方向键 / 菜单键…）。
                // 按住没有「连续产出」语义的键才不重复：
                //   - 修饰键 Shift / Ctrl / Alt / Win / Caps / Fn（按住是状态，不是连发）
                //   - 换页键（切页只有「停在哪页」，重复等于狂切）
                // 判据走 Modifiers.modifierNameFor，别用 Key.isModifier —— 那个是绘制用的，
                // 所有 k === "key" 的键都是 true（Backspace 也算）
                readonly property bool repeatable: {
                    const k = keyItem.keyData || {
                    };
                    if (!k || k.k === "spacer" || k.k === "page")
                        return false;

                    return Modifiers.modifierNameFor(k) === "";
                }

                // 按下 / 松开 / 点击各自成一个函数：手势直接调用，模拟点击也调它们，两条路共用同一份逻辑（长按重复、修饰键状态、涟漪都不会漏）
                function pressAt(px, py) {
                    keyItem.pressRipple(px, py);
                    if (repeatable) {
                        // 普通键：只发 down。走真键的键由系统的 auto-repeat 负责；
                        // 走输入法直通的键（退格/Del）系统不管，靠下面的定时器重发。
                        grid.c.keyDown(keyItem.effectiveKeyData);
                        holdTimer.restart();
                    } else {
                        // 修饰键：改状态（状态变化会同步成真实的 KEY down）
                        grid.c.modifierPressed(keyItem.keyData);
                    }
                }

                function releaseAt() {
                    holdTimer.stop();
                    repeatTimer.stop();
                    if (repeatable)
                        grid.c.keyUp(keyItem.effectiveKeyData);
                    else
                        grid.c.modifierReleased(keyItem.keyData);

                }

                // 无障碍激活：完整按下 + 松开。
                // clickAt 故意跳过 repeatable 键（避免重复注入），读屏器走它一个字都打不出来
                function activateAt() {
                    pressAt(keyItem.width / 2, keyItem.height / 2);
                    releaseAt();
                }

                function clickAt() {
                    // 无重复语义的键（换页等）仍然是「点一下」；修饰键的状态在按下时已经处理过
                    if (!repeatable)
                        grid.c.keyPressed(keyItem.effectiveKeyData);

                }

                enabled: !keyItem.isSpacer
                // 按下即触发、松开收尾；point 是当前这根手指。
                // 长按重复仍由下面两个 Timer 管（400ms 后开始重复）
                onPressedChanged: {
                    if (pressed)
                        pressAt(point.position.x, point.position.y);
                    else
                        releaseAt();
                }
                onTapped: clickAt()
                onCanceled: () => releaseAt()

            }

            // 长按重复：只对**走输入法直通**的键真的会重发（keyRepeat 内部按路由判断），
            // 走真键的键 auto-repeat 由系统负责，这两个定时器等于空转。
            // Timer 不能挂在 TapHandler 下面（pointer handler 没有 default property）。
            Timer {
                id: holdTimer

                interval: 400
                repeat: false
                onTriggered: repeatTimer.start()
            }

            Timer {
                id: repeatTimer

                interval: Math.max(20, grid.c.repeatInterval || 60)
                repeat: true
                onTriggered: grid.c.keyRepeat(keyItem.effectiveKeyData)
            }

        }

    }

    // 空格键正中间：当前输入法标识（点击仍然是空格键）
    // 有文字标签（「万」/「en」/「abc」）就显示文字，和托盘一致；
    Image {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel === "" && source !== ""
        // addon 直接给绝对路径（从 icon theme 解析），不需要缓存破除参数
        source: grid.c.fcitxImIcon === "" ? "" : "file://" + grid.c.fcitxImIcon
        width: Math.round(grid.c.keyH * 0.32)
        height: width
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + (grid.c.keyH - height) / 2
        fillMode: Image.PreserveAspectFit
        smooth: true
    }

    // 字号跟键帽主字同级（0.32）；小键宽下同样靠 HorizontalFit 缩，别触发省略
    StyledText {
        visible: grid.c.spaceEntry !== null && grid.c.fcitxImLabel !== ""
        text: grid.c.fcitxImLabel
        width: Math.round(grid.c.spaceW * 0.6)
        wrapMode: Text.NoWrap
        elide: Text.ElideNone
        fontSizeMode: Text.HorizontalFit
        minimumPixelSize: Math.min(font.pixelSize, Math.round(Theme.fontSizeSmall * 0.75))
        font.pixelSize: Math.round(grid.c.keyH * 0.32)
        font.weight: Font.Medium
        color: Theme.onSurface
        // 行框比字号高，按 height 居中会让汉字偏上（下方是 descent 空白），改用 baseline 对齐
        horizontalAlignment: Text.AlignHCenter
        x: grid.c.spaceX + (grid.c.spaceW - width) / 2
        y: grid.c.spaceY + grid.c.keyH / 2 + font.pixelSize / 2 - baselineOffset
    }

    Timer {
        id: tapTimer

        onTriggered: grid.finishPendingTap()
    }

}
