// 触控板页：多指手势区 + 左右键 + 底部把手（复用 BottomBar）。
//
// 这一层只把触摸翻译成 helper 的协议行，不碰设备、不碰事件注入。
// 坐标是**相对手势区左上角**的逻辑像素，helper 乘 ABS_SCALE 后写进 uinput，
// 所以这里绝不能混入卡片或窗口坐标。
//
// 关键：协议里的 slot 用 touchPoints 的**下标**（0..4），不能用 pointId ——
// pointId 是系统分配的，可能是 5、12 这种值，而 helper 的 ABS_MT_SLOT 只有 0..9。

import QtQuick
import "alpha.js" as Alpha
import qs.Common

Item {
    id: root

    // 卡片（KeyboardCard），借它的 pad / keyH / handleH / 颜色 token
    property var controller: null
    // 没有后端时禁用整个手势区，只留视觉
    property bool backendUp: false
    // 调试读数：证明触摸真的进来了，也方便核对坐标。默认关，排查时再打开。
    property bool showReadout: false
    property string lastReadout: ""
    // 正在按着的 slot（下标 → true），用来数手指数和过滤假 move
    property var activeSlots: ({})

    // 触点圆点直径 / 手势区最小高度（逻辑像素）
    readonly property int touchDotSize: 40
    readonly property int minSurfaceHeight: 80
    // 左右键上 "L" / "R" 的字号占按钮高度的比例
    readonly property real buttonLabelRatio: 0.28

    // 手势区实际尺寸（逻辑像素）：上层拿去当 helper 的 ABS 范围
    signal surfaceGeometry(int w, int h)
    // 原始协议行，例如 "down 0 123 456" / "btn left 1"
    signal line(string text)

    // 按键透明度：跟键盘的 keyOpacity 设置走。
    // 只乘在**底色**上，不整体 opacity —— 键盘的 Key 也是只把 bg 那个 Rectangle 调透明，
    // 文字始终实色；整体调的话触摸点和读数会一起变淡。
    readonly property real keyOpacity: root.controller ? root.controller.keyOpacity : 1
    // 按键条高度：跟随键高，触控板页不需要挤
    readonly property real buttonH: Math.round(root.controller ? root.controller.keyH * 1.1 : 70)
    // 手势区高度由 Column 自己算（body.height - 按键条 - 间隙 - 把手），
    // 不能用 root.parent.height 反推 —— 那层是卡片，比 Column 多了 pad。
    readonly property real gap: Math.round(root.controller ? root.controller.pad * 0.75 : 6)
    readonly property color fg: root.controller ? root.controller.fg : Theme.surfaceText

    function countActive() {
        return Object.keys(root.activeSlots).length;
    }

    // line 只放协议字段（"down 0 123 456"），手指数之类的读数只给人看，
    // 不能混进 socket —— helper 现在容忍，严格解析就会断
    function push(line) {
        if (root.showReadout)
            root.lastReadout = line + "  fingers=" + root.countActive();

        if (root.backendUp)
            root.line(line);
    }

    function slotDown(slot, tp) {
        root.activeSlots[slot] = true;
        root.push("down " + slot + " " + Math.round(tp.x) + " " + Math.round(tp.y));
    }

    function slotMove(slot, tp) {
        if (root.activeSlots[slot] !== true)
            return;

        root.push("move " + slot + " " + Math.round(tp.x) + " " + Math.round(tp.y));
    }

    function slotUp(slot) {
        if (root.activeSlots[slot] !== true)
            return;

        delete root.activeSlots[slot];
        root.push("up " + slot);
    }

    // 手势区尺寸在布局过程中会变两三次（先是兜底高度，再是真高度）。
    // 每次变化都发 hello 会让 helper 建两次设备、udev 枚举两遍 —— 加个 debounce，
    // 等布局稳定了只报最后一次。
    function reportGeometry() {
        geomTimer.restart();
    }

    function emitGeometry() {
        // 隐藏的页面不握手：用户没进过触控板页，系统里不该多一个指针设备
        if (!root.visible)
            return ;

        if (surface.width > 0 && surface.height > 0)
            root.surfaceGeometry(Math.round(surface.width), Math.round(surface.height));
    }

    Timer {
        id: geomTimer

        interval: 150
        onTriggered: root.emitGeometry()
    }

    Column {
        id: body

        anchors.fill: parent
        anchors.margins: root.controller ? root.controller.pad : 8
        // 底部不留 pad：把手行要贴到卡片底边（和键盘页一致）
        anchors.bottomMargin: 0
        spacing: 0

        // ── 手势区 ──────────────────────────────────────────────────
        Rectangle {
            id: surface

            width: parent.width
            height: Math.max(root.minSurfaceHeight, body.height - root.buttonH - root.gap - bottomBar.height)
            radius: Theme.cornerRadius
            // 和普通按键同色；透明度跟键盘的按键透明度设置，没后端时再压暗一档。
            // 只乘底色不用整体 opacity：否则触点圆点和读数会一起被压暗
            color: Theme.withAlpha(Theme.chipSurface, root.keyOpacity * (root.backendUp ? 1 : Alpha.Dim))
            clip: true

            onWidthChanged: root.reportGeometry()
            onHeightChanged: root.reportGeometry()
            Component.onCompleted: root.reportGeometry()

            MultiPointTouchArea {
                id: touchArea

                anchors.fill: parent
                minimumTouchPoints: 1
                maximumTouchPoints: 5
                // 触摸被合成器抢走 / 页面切走时不会再有 up，这里统一松开，
                // 否则 helper 侧 slot_active 和虚拟按键会一直按着
                onCanceled: {
                    const keys = Object.keys(root.activeSlots);
                    for (let i = 0; i < keys.length; i++)
                        root.slotUp(Number(keys[i]));
                }
                touchPoints: [
                    TouchPoint {
                        id: tp0
                    },
                    TouchPoint {
                        id: tp1
                    },
                    TouchPoint {
                        id: tp2
                    },
                    TouchPoint {
                        id: tp3
                    },
                    TouchPoint {
                        id: tp4
                    }
                ]

                // Qt6 的 TouchPoint 只是数据对象，没有自己的 pressed/updated/released 信号，
                // 只能在区域级别收事件，再按 pointId 反查是第几个触点（= ABS_MT_SLOT）。
                function slotOf(p) {
                    for (let i = 0; i < touchArea.touchPoints.length; i++) {
                        if (touchArea.touchPoints[i].pointId === p.pointId)
                            return i;
                    }
                    return -1;
                }

                onPressed: (points) => {
                    for (let k = 0; k < points.length; k++) {
                        const s = slotOf(points[k]);
                        if (s >= 0)
                            root.slotDown(s, points[k]);

                    }
                }
                onUpdated: (points) => {
                    for (let k = 0; k < points.length; k++) {
                        const s = slotOf(points[k]);
                        if (s >= 0)
                            root.slotMove(s, points[k]);

                    }
                }
                onReleased: (points) => {
                    // 抬起后 pointId 可能已经复位成 -1，按 pointId 反查会失败。
                    // 所以这里不查了：凡是「我们记着按着」但当前已经不 pressed 的 slot，全部抬起来。
                    for (let i = 0; i < touchArea.touchPoints.length; i++) {
                        if (root.activeSlots[i] === true && !touchArea.touchPoints[i].pressed)
                            root.slotUp(i);

                    }
                }
            }

            // 活动触点可视化：手指按下去应该看到圆点跟手
            Repeater {
                model: 5

                delegate: Rectangle {
                    required property int index
                    readonly property var tp: touchArea.touchPoints[index]

                    visible: tp ? tp.pressed : false
                    x: (tp ? tp.x : 0) - width / 2
                    y: (tp ? tp.y : 0) - height / 2
                    width: root.touchDotSize
                    height: root.touchDotSize
                    radius: width / 2
                    color: Theme.withAlpha(Theme.primary, Alpha.Disabled)
                    border.width: Theme.outlineWidthFocused
                    border.color: Theme.primary
                }
            }

            StyledText {
                visible: root.showReadout
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: Theme.spacingS
                text: root.backendUp ? root.lastReadout : (root.lastReadout + (root.lastReadout ? "  " : "") + I18n.trFor("inlineKeyboard", "[no backend]"))
                color: Theme.withAlpha(root.fg, Alpha.Muted)
                font.pixelSize: Theme.fontSizeSmall
            }
        }

        // 手势区 ↔ 按键条之间的留白
        Item {
            width: 1
            height: root.gap
        }

        // ── 左右键 ──────────────────────────────────────────────────
        Item {
            width: parent.width
            height: root.buttonH

            Rectangle {
                id: leftButton

                anchors.left: parent.left
                anchors.top: parent.top
                width: (parent.width - root.gap) / 2
                height: parent.height
                radius: Theme.cornerRadius
                // 修饰键同色；按下时和键盘的锁定态一样用 primary 实心。
                // 透明度只乘底色（和键盘 Key 的 bg.opacity 等价），文字保持实色。
                color: Theme.withAlpha(leftArea.pressed ? Theme.primary : Theme.chipSurfaceNested, root.keyOpacity)

                StyledText {
                    anchors.centerIn: parent
                    text: "L"
                    color: leftArea.pressed ? Theme.onPrimary : Theme.withAlpha(root.fg, 0.7)
                    font.pixelSize: Math.round(root.buttonH * root.buttonLabelRatio)
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: leftArea

                    anchors.fill: parent
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.trFor("inlineKeyboard", "Left click")
                    onPressed: root.push("btn left 1")
                    onReleased: root.push("btn left 0")
                    onCanceled: root.push("btn left 0")
                }
            }

            Rectangle {
                id: rightButton

                anchors.right: parent.right
                anchors.top: parent.top
                width: (parent.width - root.gap) / 2
                height: parent.height
                radius: Theme.cornerRadius
                // 修饰键同色；按下时和键盘的锁定态一样用 primary 实心。
                // 透明度只乘底色（和键盘 Key 的 bg.opacity 等价），文字保持实色。
                color: Theme.withAlpha(rightArea.pressed ? Theme.primary : Theme.chipSurfaceNested, root.keyOpacity)

                StyledText {
                    anchors.centerIn: parent
                    text: "R"
                    color: rightArea.pressed ? Theme.onPrimary : Theme.withAlpha(root.fg, 0.7)
                    font.pixelSize: Math.round(root.buttonH * root.buttonLabelRatio)
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: rightArea

                    anchors.fill: parent
                    Accessible.role: Accessible.Button
                    Accessible.name: I18n.trFor("inlineKeyboard", "Right click")
                    onPressed: root.push("btn right 1")
                    onReleased: root.push("btn right 0")
                    onCanceled: root.push("btn right 0")
                }
            }
        }

        // ── 底部把手（复用键盘那套：收起 / 拖动 / 输入法）──
        // 键盘页另有一个实例，两个不同时可见。状态全在 controller 上（这里不存副本），
        // 所以两边不会分叉；只有按下态的 longFired 是各自的，且只有一个在屏幕上。
        BottomBar {
            id: bottomBar

            controller: root.controller
        }
    }
}
