// 语音模式窗口：一条浮动胶囊，只放 VoiceBar 一行。
// 和 FloatingKeyboardWindow 是两种布局（宽度包内容、高度一行、圆角取一半）。
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Widgets

PanelWindow {
    id: voiceWindow

    property var controller: null

    KeyboardMetrics {
        id: metrics
        kbWidth: controller ? controller.savedW : 1050
        kbHeight: controller ? controller.kbHeight : 444
        // daemon 上没有 screen 属性（那是窗口才有的），
        // 直接问 Quickshell 要主屏尺寸
        screenW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
        screenH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
    }

    // 一行的高度（和主键盘顶部那一行一致）
    readonly property real rowH: Math.max(metrics.quickH, metrics.candH)
    readonly property real capH: rowH + Math.round(metrics.pad * 2)
    // 宽度跟随主键盘的**名义宽度**（keyboardWidth），不跟全宽模式：
    // 铺满时 cardW 会等于屏幕宽，那对一条语音条来说太长了。
    readonly property real capW: Math.min(metrics.kbWidth,
                                         metrics.screenW - metrics.pad * 4)

    // 语音模式需要 vinput 存在；没装时这个窗口不该出现
    visible: controller ? (controller.voiceMinimal && controller.voiceAvailable) : false

    color: "transparent"

    // 可拖动：锚点和 margins 配合（layer-shell 不能改 x/y，只能调 margins）。
    // 默认水平居中、贴屏幕底部；用户拖过之后用自己记的位置。
    property real posX: Math.round((metrics.screenW - capW) / 2)
    property real posY: 0

    anchors {
        bottom: true
        left: true
    }

    margins {
        left: Math.round(Math.max(0, Math.min(metrics.screenW - capW, posX)))
        bottom: Math.round(Math.max(0, Math.min(metrics.screenH - capH, posY)))
    }

    // 每次进入语音模式重新居中、贴底（onVisibleChanged 只能有一个）
    onVisibleChanged: {
        if (visible) {
            posX = Math.round((metrics.screenW - capW) / 2)
            posY = 0
        }
    }

    // 浮动：不参与其它窗口的避让计算
    WlrLayershell.namespace: "dms:plugins:inlineKeyboard:voice"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // 窗口尺寸就是胶囊尺寸
    implicitWidth: capW
    implicitHeight: capH

    // mask 同时是指针输入区域；不可见时收成 0，否则隐藏后仍会吃点击
    mask: Region {
        x: 0
        y: 0
        width: voiceWindow.visible ? Math.round(voiceWindow.width) : 0
        height: voiceWindow.visible ? Math.round(voiceWindow.height) : 0
    }


    // 描边画在背景外面，否则会被 VoiceBar 自己的背景盖住内边缘
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: "transparent"
        border.width: 2
        border.color: Theme.withAlpha(Theme.primary, 0.5)
    }

    Rectangle {
        id: capsule
        anchors.fill: parent
        anchors.margins: 2
        radius: height / 2
        color: Theme.withAlpha(Theme.surface, controller ? controller.bgOpacity : 1.0)

        // 一行内容：左缩小 / 中文字 / 右麦克风
        VoiceBar {
            anchors.fill: parent
            // 拖动由 VoiceBar 中间文字区发起，这里只负责移动窗口
            onDragRequested: (dx, dy) => {
                voiceWindow.posX = Math.max(0, Math.min(metrics.screenW - capW,
                                                      voiceWindow.posX + dx))
                voiceWindow.posY = Math.max(0, Math.min(metrics.screenH - capH,
                                                      voiceWindow.posY - dy))
            }
            controller: voiceWindow.controller
            metrics: metrics
        }
    }
}
