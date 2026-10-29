import QtQuick
import qs.Common
import Qt5Compat.GraphicalEffects

// 可复用的按压涟漪：按下时从触点扩散、并在按住期间保持；松开才淡出消失。
// 用法：
//   Ripple { id: r; anchors.fill: parent; cornerRadius: ... }
//   MouseArea {
//       onPressed: mouse => r.press(mouse.x, mouse.y)
//       onReleased: r.release()
//       onCanceled: r.release()          // 按住后拖出去也要收掉
//   }
// 一次性模拟点击（不想改调用方）可以用 trigger()，等于 press + release。
Item {
    id: root

    // 裁剪圆角（圆形按钮传 width / 2）
    property real cornerRadius: 0
    property color rippleColor: Theme.primary
    property real peakOpacity: 0.45
    // 扩散速度：短一点，按住时看起来是「亮起来」而不是慢慢长大
    property int expandDuration: 220
    property int fadeDuration: 180
    // 按住中：为 true 时保持不透明度，松开后转 false 再淡出
    property bool pressed: false

    // 只在按住或淡出期间渲染，省掉常驻 layer 开销
    visible: root.pressed || fadeAnim.running
    layer.enabled: visible
    layer.effect: OpacityMask {
        maskSource: rippleMask
    }

    // 扩散后的直径：按「对角线 × 2.1」取。
    // 圆心在触点上，点在角落时到对角的距离就是 √(w²+h²)，
    // 用 2.1×最长边（半径只有 1.05×边长）那一侧会盖不满，边缘看着缺一块；
    // 多出来的 5% 是留给抗锯齿的余量，避免圆周正好压在对角点上。
    readonly property real maxSize: 2.1 * Math.sqrt(root.width * root.width
                                                    + root.height * root.height)

    function press(px, py) {
        rippleHost.x = px
        rippleHost.y = py
        fadeAnim.stop()
        root.pressed = true
        rippleCircle.opacity = root.peakOpacity
        expandAnim.restart()
    }

    function release() {
        if (!root.pressed && !fadeAnim.running)
            return
        root.pressed = false
        expandAnim.stop()
        fadeAnim.restart()
    }

    function trigger(px, py) {
        root.press(px, py)
        root.release()
    }

    // 遮罩源：和宿主同圆角的矩形
    Item {
        id: rippleMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: root.cornerRadius
            color: Theme.onSurface
            antialiasing: true
        }
    }

    Item {
        id: rippleHost
        width: 0
        height: 0

        Rectangle {
            id: rippleCircle
            anchors.centerIn: parent
            width: 0
            height: 0
            radius: width / 2
            opacity: root.peakOpacity
            color: root.rippleColor
            antialiasing: true
        }
    }

    ParallelAnimation {
        id: expandAnim
        NumberAnimation {
            target: rippleCircle
            property: "width"
            from: 0
            to: root.maxSize
            duration: root.expandDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: rippleCircle
            property: "height"
            from: 0
            to: root.maxSize
            duration: root.expandDuration
            easing.type: Easing.OutCubic
        }
    }

    NumberAnimation {
        id: fadeAnim
        target: rippleCircle
        property: "opacity"
        to: 0
        duration: root.fadeDuration
        easing.type: Easing.OutCubic
    }
}
